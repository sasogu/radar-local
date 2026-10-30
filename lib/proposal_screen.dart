import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/proposal.dart';
import 'core/radar.dart';
import 'services/proposal_store.dart';

const radarIssueUrl =
    'https://github.com/sasogu/radar-local/issues/new?template=radar-proposal.yml';

class ProposalScreen extends StatefulWidget {
  const ProposalScreen({
    required this.store,
    required this.language,
    super.key,
  });
  final ProposalStore store;
  final String language;
  @override
  State<ProposalScreen> createState() => _ProposalScreenState();
}

class _ProposalScreenState extends State<ProposalScreen> {
  bool get va => widget.language == 'va';
  String tr(String a, String b) => va ? a : b;

  String kindLabel(ProposedRadarKind kind) => switch (kind) {
    ProposedRadarKind.unknown => tr('Per determinar', 'Por determinar'),
    ProposedRadarKind.fixed => tr('Fix', 'Fijo'),
    ProposedRadarKind.section => tr('De tram', 'De tramo'),
    ProposedRadarKind.redLight => tr('De semàfor', 'De semáforo'),
    ProposedRadarKind.phone => tr(
      'Càmera de cinturó i mòbil',
      'Cámara de cinturón y móvil',
    ),
  };

  String report(RadarProposal proposal) => [
    tr(
      'Proposta de radar pendent de verificació',
      'Propuesta de radar pendiente de verificación',
    ),
    '${tr('Tipus', 'Tipo')}: ${kindLabel(proposal.kind)}',
    'Latitud: ${proposal.point.lat.toStringAsFixed(6)}',
    'Longitud: ${proposal.point.lon.toStringAsFixed(6)}',
    if (proposal.accuracy != null)
      '${tr('Precisió GPS', 'Precisión GPS')}: ${proposal.accuracy!.round()} m',
    if (proposal.heading != null)
      '${tr('Rumb GPS', 'Rumbo GPS')}: ${proposal.heading!.round()}°',
    '${tr('Data', 'Fecha')}: ${proposal.createdAt.toLocal().toIso8601String()}',
    '${tr('Nota', 'Nota')}: ${proposal.note.isEmpty ? '—' : proposal.note}',
    tr(
      'Verifiqueu la ubicació i la font abans de publicar.',
      'Verificad la ubicación y la fuente antes de publicar.',
    ),
  ].join('\n');

  Future<void> edit([RadarProposal? proposal]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProposalEditor(
          store: widget.store,
          language: widget.language,
          proposal: proposal,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> copy(RadarProposal proposal) async {
    await Clipboard.setData(ClipboardData(text: report(proposal)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Proposta copiada. Revisa-la abans d’enviar-la.',
              'Propuesta copiada. Revísala antes de enviarla.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> openIssue() async {
    final opened = await launchUrl(
      Uri.parse(radarIssueUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('No s’ha pogut obrir GitHub', 'No se ha podido abrir GitHub'),
          ),
        ),
      );
    }
  }

  Future<void> delete(RadarProposal proposal) async {
    await widget.store.remove(proposal.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final proposals = widget.store.all();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Propostes de radars', 'Propuestas de radares')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(),
        icon: const Icon(Icons.add_location_alt),
        label: Text(tr('Nova proposta', 'Nueva propuesta')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text(
            tr(
              'Les propostes es guarden només en este dispositiu. Copia i revisa la proposta; després obri GitHub i apega-la en una incidència. L’app no envia coordenades.',
              'Las propuestas se guardan solo en este dispositivo. Copia y revisa la propuesta; después abre GitHub y pégala en una incidencia. La app no envía coordenadas.',
            ),
          ),
          const SizedBox(height: 16),
          if (proposals.isEmpty)
            Text(
              tr('Encara no hi ha propostes.', 'Todavía no hay propuestas.'),
            ),
          for (final proposal in proposals)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${kindLabel(proposal.kind)} · ${proposal.point.lat.toStringAsFixed(5)}, ${proposal.point.lon.toStringAsFixed(5)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      proposal.createdAt.toLocal().toString().split('.').first,
                    ),
                    if (proposal.note.isNotEmpty) Text(proposal.note),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => edit(proposal),
                          icon: const Icon(Icons.edit),
                          label: Text(tr('Revisa', 'Revisar')),
                        ),
                        TextButton.icon(
                          onPressed: () => copy(proposal),
                          icon: const Icon(Icons.copy),
                          label: Text(tr('Copia', 'Copiar')),
                        ),
                        TextButton.icon(
                          onPressed: openIssue,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('GitHub'),
                        ),
                        TextButton.icon(
                          onPressed: () => delete(proposal),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(tr('Elimina', 'Eliminar')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ProposalEditor extends StatefulWidget {
  const ProposalEditor({
    required this.store,
    required this.language,
    this.proposal,
    super.key,
  });
  final ProposalStore store;
  final String language;
  final RadarProposal? proposal;
  @override
  State<ProposalEditor> createState() => _ProposalEditorState();
}

class _ProposalEditorState extends State<ProposalEditor> {
  late final TextEditingController lat = TextEditingController(
    text: widget.proposal?.point.lat.toString() ?? '',
  );
  late final TextEditingController lon = TextEditingController(
    text: widget.proposal?.point.lon.toString() ?? '',
  );
  late final TextEditingController note = TextEditingController(
    text: widget.proposal?.note ?? '',
  );
  late ProposedRadarKind kind =
      widget.proposal?.kind ?? ProposedRadarKind.unknown;
  bool get va => widget.language == 'va';
  String tr(String a, String b) => va ? a : b;
  @override
  void dispose() {
    lat.dispose();
    lon.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    try {
      final latitude = double.tryParse(lat.text.trim().replaceAll(',', '.'));
      final longitude = double.tryParse(lon.text.trim().replaceAll(',', '.'));
      if (latitude == null || longitude == null) {
        throw const FormatException('Coordinates required');
      }
      final original = widget.proposal;
      final proposal = RadarProposal(
        id: original?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        point: Point(latitude, longitude),
        createdAt: original?.createdAt ?? DateTime.now().toUtc(),
        kind: kind,
        accuracy: original?.accuracy,
        heading: original?.heading,
        note: note.text.trim(),
      );
      await widget.store.save(proposal);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Revisa les coordenades i la nota: $error',
                'Revisa las coordenadas y la nota: $error',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Revisa la proposta', 'Revisar propuesta'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          tr(
            'Confirma la ubicació abans de copiar-la. No s’afegeix a la base de radars fins que s’haja verificat.',
            'Confirma la ubicación antes de copiarla. No se añade a la base de radares hasta que se haya verificado.',
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: lat,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(labelText: tr('Latitud', 'Latitud')),
        ),
        TextField(
          controller: lon,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(labelText: tr('Longitud', 'Longitud')),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ProposedRadarKind>(
          initialValue: kind,
          decoration: InputDecoration(labelText: tr('Tipus', 'Tipo')),
          items: [
            DropdownMenuItem(
              value: ProposedRadarKind.unknown,
              child: Text(tr('Per determinar', 'Por determinar')),
            ),
            DropdownMenuItem(
              value: ProposedRadarKind.fixed,
              child: Text(tr('Fix', 'Fijo')),
            ),
            DropdownMenuItem(
              value: ProposedRadarKind.section,
              child: Text(tr('De tram', 'De tramo')),
            ),
            DropdownMenuItem(
              value: ProposedRadarKind.redLight,
              child: Text(tr('De semàfor', 'De semáforo')),
            ),
            DropdownMenuItem(
              value: ProposedRadarKind.phone,
              child: Text(
                tr('Càmera de cinturó i mòbil', 'Cámara de cinturón y móvil'),
              ),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => kind = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          maxLength: 500,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: tr('Nota i font (opcional)', 'Nota y fuente (opcional)'),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: save,
          icon: const Icon(Icons.save),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          label: Text(tr('Guarda localment', 'Guardar localmente')),
        ),
      ],
    ),
  );
}
