# Privacitat

El GPS es processa en memòria dins del dispositiu i no es desa ni s'envia. No hi ha analítica, comptes d'usuari, anuncis ni servidor propi. La base inicial de Madrid s'inclou dins de l'app; les bases importades i les preferències es guarden a l'espai privat de l'app. Desinstal·lar l'app esborra aquestes dades segons el comportament del sistema.

L'única connexió de xarxa de l'app és la descàrrega de dades JSON des d'una URL HTTPS que l'usuari configura. Es pot iniciar manualment amb «Actualitza ara». L'actualització automàtica és optativa i es comprova en obrir l'app com a màxim una vegada cada set dies; no es consulta durant la conducció. El servidor de la font pot veure la IP i la petició HTTP, però no rep coordenades GPS de l'app. A Android només se seleccionen veus TTS marcades pel sistema com a offline; si no n'hi ha, es fa servir únicament el so. A iOS la veu depèn del sistema operatiu i s'ha de validar en dispositiu abans de publicar.

Permisos Android: ubicació precisa mentre s'usa l'app, servei en primer pla i notificacions per mostrar que el GPS continua actiu. Internet només per a actualitzacions optatives. iOS: ubicació mentre s'usa l'app. No es demana ubicació permanent.
