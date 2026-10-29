// n8n Code node: watch upstream files, persist only digests, alert on changes.
const https = require('https');
const fs = require('fs');
const crypto = require('crypto');

const statePath = '/home/node/.n8n/radar-sources-state.json';
const sources = [
  ['DGT oficial', 'https://www.dgt.es/conoce-el-estado-del-trafico/vigilancia-y-control/equipos-y-tramos-de-vigilancia/'],
  ['DGT/Tachwire', 'https://tachwire.app/data/cameras/es.json'],
  ['Catalunya/SCT', 'https://transit.gencat.cat/web/.content/documents/seguretat_viaria/radars.txt'],
  ['Madrid', 'https://datos.madrid.es/dataset/300049-0-radares-fijos-moviles/resource/300049-1-radares-fijos-moviles-csv/download/300049-1-radares-fijos-moviles-csv.csv'],
];

function download(url, redirects = 0, collect = false) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, {headers: {'User-Agent': 'RadarLocalSourceMonitor/1.0'}}, response => {
      if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
        response.resume();
        if (redirects >= 3 || !response.headers.location) return reject(new Error('Too many redirects'));
        const next = new URL(response.headers.location, url);
        if (next.protocol !== 'https:') return reject(new Error('Insecure redirect'));
        return resolve(download(next.toString(), redirects + 1, collect));
      }
      if (response.statusCode !== 200) {
        response.resume();
        return reject(new Error(`HTTP ${response.statusCode}`));
      }
      const hash = crypto.createHash('sha256');
      let bytes = 0;
      const chunks = [];
      response.on('data', chunk => {
        bytes += chunk.length;
        if (bytes > 25 * 1024 * 1024) response.destroy(new Error('Source too large'));
        else {
          hash.update(chunk);
          if (collect) chunks.push(chunk);
        }
      });
      response.on('end', () => {
        if (bytes < 100) return reject(new Error('Response too small'));
        resolve({digest: hash.digest('hex'), bytes, body: collect ? Buffer.concat(chunks).toString('utf8') : undefined});
      });
      response.on('error', reject);
    });
    request.setTimeout(20000, () => request.destroy(new Error('Timeout')));
    request.on('error', reject);
  });
}

let prior = {};
try { prior = JSON.parse(fs.readFileSync(statePath, 'utf8')); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const next = {...prior};
const changed = [];
const errors = [];
const currentErrors = {};
for (const [name, url] of sources) {
  try {
    let result;
    if (name === 'DGT oficial') {
      const page = await download(url, 0, true);
      const match = page.body.match(/(?:https?:\/\/[^"'\s<>]+)?\/export\/sites\/web-DGT\/[^"'\s<>]*INFORME_CINEMOMETROS[^"'\s<>]*\.pdf/i);
      if (!match) throw new Error('DGT PDF link not found');
      result = await download(new URL(match[0], url).toString());
    } else result = await download(url);
    if (prior[url] && prior[url] !== result.digest) changed.push({name, url});
    next[url] = result.digest;
  } catch (error) {
    currentErrors[url] = error.message;
    if (prior.__errors?.[url] !== error.message) errors.push(`${name}: ${error.message}`);
  }
}
if (Object.keys(currentErrors).length) next.__errors = currentErrors;
else delete next.__errors;
if (JSON.stringify(next) !== JSON.stringify(prior)) {
  const temp = `${statePath}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(next), {mode: 0o600});
  fs.renameSync(temp, statePath);
}
if (!changed.length && !errors.length) return [];
const lines = [
  'Radar Local: revisió de fonts',
  ...changed.map(({name, url}) => `Canvi detectat: ${name}\n${url}`),
  ...errors.map(error => `Error de consulta: ${error}`),
  'Cal validar les coordenades i la llicència abans de publicar un JSON nou.',
];
return [{json: {text: lines.join('\n\n')}}];
