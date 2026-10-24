export const meta = {
  name: 'verification-audit',
  description: 'Консилиум: хватает ли Quint и проверок для логики двух машин состояний — 5 аналитиков, 3 аудитора, итог',
  whenToUse: 'Аудит проверки логики машины инцидента и машины сценариев. Промпты — prompts/verification-pipeline-audit.md. args: {date: "ГГГГ-ММ-ДД"}',
  phases: [
    { title: 'Аналитики', detail: 'А1–А5 независимо, не больше трёх сразу, каждый пишет a<N>.md' },
    { title: 'Аудит', detail: 'три аудитора, утверждения поделены по вопросам' },
    { title: 'Консилиум', detail: 'итог из подтверждённого и таблица решений' },
  ],
}

// Тексты промптов — в prompts/verification-pipeline-audit.md, здесь только порядок запуска.
// Агенты читают их сами, поэтому правка промпта не требует правки сценария.
const PROMPTS = 'prompts/verification-pipeline-audit.md'

const date = args && args.date
if (!/^\d{4}-\d{2}-\d{2}$/.test(date || '')) {
  throw new Error('Нужна дата запуска: args = {date: "ГГГГ-ММ-ДД"}')
}
const dir = `reviews/${date}/verification`

const ANALYSTS = [
  { role: 'А1', file: 'a1.md' },
  { role: 'А2', file: 'a2.md' },
  { role: 'А3', file: 'a3.md' },
  { role: 'А4', file: 'a4.md' },
  { role: 'А5', file: 'a5.md' },
]

// Аудиторы делят утверждения по вопросам, чтобы одинаковые утверждения разных аналитиков
// попали к одному аудитору и были сведены вместе.
const AUDITORS = [
  { n: 1, questions: '1, 6, 7' },
  { n: 2, questions: '3, 4' },
  { n: 3, questions: '2, 5' },
]

const WRITTEN = {
  type: 'object',
  properties: {
    path: { type: 'string', description: 'Файл, куда записан ответ' },
    items: { type: 'integer', description: 'Сколько утверждений (у аудитора — проверенных)' },
    summary: { type: 'string', description: 'Главное в 2–3 фразах' },
  },
  required: ['path', 'items', 'summary'],
}

const CONSILIUM = {
  type: 'object',
  properties: {
    path: { type: 'string' },
    critical: { type: 'integer', description: 'Сколько дыр «критично»' },
    decisions: { type: 'integer', description: 'Сколько строк в таблице решений' },
    summary: { type: 'string', description: 'Вывод: хватает ли Quint, 2–3 фразы' },
  },
  required: ['path', 'critical', 'decisions', 'summary'],
}

const own = path => `Запиши ответ целиком в ${path} (каталог создай, если его нет). ` +
  'Больше ничего в репозитории не меняй и не коммить. Раздел «Как запускать» в файле промптов — для человека, пропусти его.'

// Не больше трёх аналитиков сразу: пятеро вместе со своими quint и Chrome переполнили
// память (14 ГБ), 2026-10-24 упал VS Code.
const BATCH = 3

phase('Аналитики')
const analysts = []
for (let i = 0; i < ANALYSTS.length; i += BATCH) {
  analysts.push(...(await parallel(ANALYSTS.slice(i, i + BATCH).map(a => () => agent(
    `Ты — аналитик ${a.role}. Открой ${PROMPTS}: твои инструкции — блоки «Общая часть — всем агентам» ` +
    `и «Аналитик», твоя роль — ${a.role}. Работай независимо: файлы других аналитиков в ${dir} не читай. ` +
    own(`${dir}/${a.file}`),
    { label: a.role, phase: 'Аналитики', schema: WRITTEN },
  )))).filter(Boolean))
}

if (analysts.length < ANALYSTS.length) {
  log(`Ответили ${analysts.length} из ${ANALYSTS.length} аналитиков — аудит идёт по тем, что есть`)
}
if (!analysts.length) throw new Error('Ни один аналитик не ответил')
const answers = analysts.map(a => a.path).join(', ')

phase('Аудит')
const audits = (await parallel(AUDITORS.map(x => () => agent(
  `Ты — аудитор ${x.n} из ${AUDITORS.length}. Открой ${PROMPTS}: твои инструкции — блоки ` +
  `«Общая часть — всем агентам» и «Аудитор». Ответы аналитиков: ${answers}. ` +
  `Проверяй только утверждения по вопросам ${x.questions} — остальные проверяют другие аудиторы. ` +
  own(`${dir}/audit-${x.n}.md`),
  { label: `аудитор ${x.n}`, phase: 'Аудит', schema: WRITTEN },
)))).filter(Boolean)

if (audits.length < AUDITORS.length) {
  log(`Ответили ${audits.length} из ${AUDITORS.length} аудиторов — часть утверждений не проверена, консилиум это отметит`)
}

phase('Консилиум')
const consilium = await agent(
  `Ты — председатель консилиума. Открой ${PROMPTS}: твои инструкции — блоки «Общая часть — всем агентам» ` +
  `и «Консилиум». Ответы аналитиков: ${answers}. Отчёты аудиторов: ${audits.map(a => a.path).join(', ') || 'нет'}. ` +
  `Аудиторы делили утверждения по вопросам: ${AUDITORS.map(x => `${x.n} — ${x.questions}`).join('; ')}. ` +
  'Утверждения вопросов, чей аудитор не ответил, — «не проверить». ' +
  own(`${dir}/consilium.md`),
  { label: 'консилиум', phase: 'Консилиум', schema: CONSILIUM },
)

return { analysts, audits, consilium }
