// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { en } from './en'

type CatalogShape<T> = {
  readonly [Key in keyof T]: T[Key] extends string ? string : CatalogShape<T[Key]>
}

export const es = {
  app: {
    name: 'zownload',
  },
  header: {
    language: 'Idioma',
    settings: 'Configuración',
    english: 'Inglés',
    spanish: 'Español',
    switchToEnglish: 'Cambiar a inglés',
    switchToSpanish: 'Cambiar a español',
  },
  navigation: {
    back: 'Volver a descargas',
  },
  input: {
    title: 'Descargar',
    urlLabel: 'Introduce la URL',
    analyze: 'Analizar',
    urlPlaceholder: 'https://...',
    formatLabel: 'Formato',
    mp3: 'MP3 (Audio)',
    mp4: 'MP4 (Video)',
    convert: 'Convertir',
    analyzing: 'Analizando',
  },
  download: {
    back: 'Volver',
    quality: 'Calidad',
    requestedMaximum: 'Máximo solicitado',
    maxQuality: 'Calidad máxima',
    minQuality: 'Calidad mínima',
    download: 'Descargar',
    enqueuing: 'Añadiendo a la cola',
    duration: 'Duración',
    site: 'Sitio',
    itemCount: 'Elementos',
    itemsInList: 'Elementos de la lista',
    thumbnailUnavailable: 'Miniatura no disponible',
  },
  queue: {
    title: 'Cola',
    empty: 'No hay descargas activas',
  },
  history: {
    title: 'Historial',
    empty: 'Aún no hay historial',
  },
  settings: {
    title: 'Configuración',
    language: 'Idioma',
  },
  errors: {
    invalid_url: 'Introduce una URL válida.',
    unsupported_site: 'Este sitio no es compatible.',
    private_or_restricted: 'Este video es privado o tiene acceso restringido.',
    not_found: 'No se encontró el video o la lista de reproducción.',
    no_internet: 'Sin conexión a internet.',
    disk_full: 'No hay suficiente espacio de almacenamiento.',
    permission_denied: 'Se denegó el permiso de almacenamiento.',
    engine_missing: 'El motor de descargas no está disponible.',
    unknown: 'Ocurrió un error.',
  },
} as const satisfies CatalogShape<typeof en>
