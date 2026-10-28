// -*- mode: Bluespec; -*-
// Собрано скриптом tools/gen_quint.mjs из Specification/Workflow_machine/workflow_schema.v1.json и частей quint/src/.
// Руками не править: правится машина или часть в src/, затем сборка.
/* Машина состояний инцидента МИ — формальная модель на Quint (ARCH-07.6).

   Типы, значения настроек, определения, условия и эффекты переходов — из машины
   ../workflow_schema.v1.json, переводом её выражений CEL (CEL.md, «Перевод в Quint»): смысл правил
   записан один раз, и модель проверяет те же правила, что исполняет прототип. Руками — части src/:
   мир модели (world.qnt), ядро исполнения (core.qnt), инварианты (invariants.qnt).

   Мир маленький: 3 инцидента, 2 оператора, 1 дежурная группа. Время — целые миллисекунды, как в
   машине; часы идут действием окружения «время» к следующему событию — дедлайну, концу окна после
   дедлайна, порогу молчания, концу срока переоткрытия, — поэтому нормативы и сроки — значения машины.

   Запуск: quint run im.qnt --invariant inv */
module im {

  /* ===== Контекст перехода ===== */

  // Кто проверяет условия (me) и кто выполняет (actor), когда, форма, где спрашивают, инцидент до перехода
  type Ctx = { me: str, actor: str, now: int, deadline: int, form: Form, surface: str, before: Incident }
  // Инциденты и отвеченные шаги сценария: эффекты переходов меняют только это
  type World = { inc: str -> Incident, answers: str -> Set[str] }
  type Transition = { id: str, trigger: str, actor: str, from: Set[str], timer: str, idleSec: int, ownedByAgent: bool, surfaces: Set[str], bulkOnly: bool }
  // Последнее действие — с параметрами: по ним историю модели повторяют на исполнителе прототипа
  // (tools/check_quint_replay.mjs). others — набор объединения, prio, scenario и event — у появления
  type Action = { name: str, actor: str, incident: str, kind: str, form: Form, surface: str, others: List[str], prio: int, scenario: str, event: str }

  /* ===== Типы машины (cel.types) ===== */


  type Incident = { id: str, number: str, eventType: str, priority: int, occurredAt: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str, eventGuid: str }

  type Timer = { due: int, paused: bool, left: int, fired: int, since: int }

  type Breach = { kind: str, at: int, owner: str }

  type LeftGroup = { primaryId: str, linkedAt: int, at: int }

  type Form = { targetId: str, primaryId: str, resultId: str, reasonId: str, causeId: str, comment: str }

  type Limits = { maxActive: int, maxOnHold: int, maxBulk: int, reopenWindowMin: int, reopenResolutionSec: int }

  type SessionState = { id: str, readOnly: bool, readOnlyReasonKey: str }

  type Session = { states: List[SessionState], heartbeatSec: int, idleHoldSec: int, idleReleaseSec: int }

  type Escalation = { enabled: bool, levels: List[Level], maxLevel: int, onResolutionOverdue: str }

  type Level = { level: int, targetKind: str, target: str, reactionSec: int }

  type Alerts = { targetKind: str, target: str, noRecipientLog: str }

  type State = { id: str, category: str }

  type CloseResultItem = { id: str, labelKey: str, permission: str, fromStates: List[str], ownerOnlyInStates: List[str], surfaces: List[str], requiredStepSet: str, commentRequired: bool, finish: bool }

  type ScopeRule = { own: ScopeOwn }

  type ScopeOwn = { anyOf: List[ScopeCond] }

  type ScopeCond = { state: str, ownership: str }

  type TimerDef = { id: str, labelKey: str, defaultSec: int, byPriority: int -> int, overridesBy: List[str], overrides: List[Override], keepsLeft: bool, startsOnce: bool, pausable: bool, secFrom: str }

  type Override = { eventType: List[str], priority: List[int], sourceGroup: List[str], scenario: List[str], sec: int }

  type HoldReason = { id: str, maxMinutes: List[int], setBy: str, deadlineFromIdle: bool }

  type Event = { guid: str, eventType: str, device: str, deviceType: str }

  type Condition = { eventType: List[str], device: List[str], deviceType: List[str], group: List[str] }

  type Rule = { guid: str, priority: int, createdAt: int, scenarios: List[str], conditions: List[Condition] }

  type Settings = { limits: Limits, session: Session, escalation: Escalation, alerts: Alerts, states: List[State], closeResults: List[CloseResultItem], timerDefs: List[TimerDef], holdReasons: List[HoldReason] }


  /* ===== Настройки — значения машины (cel.settings) ===== */


  pure val MACHINE_SETTINGS: Settings = {
    limits: { maxActive: 0, maxOnHold: 5, maxBulk: 0, reopenWindowMin: 1440, reopenResolutionSec: 0 },
    session: { states: [{ id: "ready", readOnly: false, readOnlyReasonKey: "" }, { id: "busy", readOnly: false, readOnlyReasonKey: "" }, { id: "not_ready", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.not_ready" }, { id: "offline", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.offline" }], heartbeatSec: 30, idleHoldSec: 300, idleReleaseSec: 1200 },
    escalation: { enabled: true, levels: [{ level: 1, targetKind: "user", target: "petrova", reactionSec: 120 }, { level: 2, targetKind: "user", target: "noc", reactionSec: 90 }], maxLevel: 2, onResolutionOverdue: "alert" },
    alerts: { targetKind: "group", target: "grp-leads", noRecipientLog: "workflow.journal.alert_no_recipient" },
    states: [{ id: "new", category: "pending" }, { id: "pending_acceptance", category: "pending" }, { id: "in_progress", category: "active" }, { id: "on_hold", category: "active" }, { id: "closed", category: "done" }, { id: "linked", category: "linked" }],
    closeResults: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "closing", commentRequired: false, finish: true }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", permission: "incident:close:unprocessed", fromStates: ["new", "pending_acceptance", "in_progress", "on_hold"], ownerOnlyInStates: ["in_progress", "on_hold"], surfaces: ["queue", "card"], requiredStepSet: "none", commentRequired: true, finish: false }],
    timerDefs: [{ id: "reaction", labelKey: "workflow.timer.reaction", defaultSec: 300, byPriority: Map(), overridesBy: ["eventType", "priority", "sourceGroup", "scenario"], overrides: [{ eventType: [], priority: [100], sourceGroup: [], scenario: [], sec: 240 }, { eventType: [], priority: [75], sourceGroup: [], scenario: [], sec: 420 }, { eventType: [], priority: [50], sourceGroup: [], scenario: [], sec: 900 }, { eventType: [], priority: [25], sourceGroup: [], scenario: [], sec: 1800 }], keepsLeft: true, startsOnce: false, pausable: false, secFrom: "" }, { id: "resolution", labelKey: "workflow.timer.resolution", defaultSec: 900, byPriority: Map(25 -> 1800, 50 -> 1500, 75 -> 900, 100 -> 600), overridesBy: ["eventType", "priority", "sourceGroup", "scenario"], overrides: [], keepsLeft: false, startsOnce: true, pausable: true, secFrom: "" }, { id: "hold", labelKey: "workflow.timer.hold", defaultSec: 0, byPriority: Map(), overridesBy: [], overrides: [], keepsLeft: false, startsOnce: false, pausable: false, secFrom: "reasonCatalogs.hold[].maxMinutes" }],
    holdReasons: [{ id: "third_party", maxMinutes: [30], setBy: "operator", deadlineFromIdle: false }, { id: "patrol", maxMinutes: [45], setBy: "operator", deadlineFromIdle: false }, { id: "no_data", maxMinutes: [60], setBy: "operator", deadlineFromIdle: false }, { id: "break", maxMinutes: [30], setBy: "system", deadlineFromIdle: false }, { id: "no_link", maxMinutes: [], setBy: "system", deadlineFromIdle: true }],
  }

  pure val STATES: Set[str] = Set("new", "pending_acceptance", "in_progress", "on_hold", "closed", "linked")

  pure val AGENT_MOVES: Set[{ id: str, from: Set[str], to: str, permission: str }] = Set({ id: "break", from: Set("ready"), to: "not_ready", permission: "agent:set_not_ready" }, { id: "back", from: Set("not_ready"), to: "ready", permission: "" }, { id: "sign_out", from: Set("ready", "not_ready"), to: "offline", permission: "" }, { id: "sign_in", from: Set("offline"), to: "ready", permission: "" })

  pure val AGENT_STARTS: Set[str] = Set("offline", "ready")


  // Настройки, от которых зависят ветки автоматических переходов, — все сочетания (PROC-43)

  type Branches = { escalation_enabled: bool, escalation_onResolutionOverdue: str }

  pure val BRANCH_SETTINGS: Set[Branches] = Set(
    { escalation_enabled: true, escalation_onResolutionOverdue: "alert" },
    { escalation_enabled: true, escalation_onResolutionOverdue: "escalate" },
    { escalation_enabled: false, escalation_onResolutionOverdue: "alert" },
    { escalation_enabled: false, escalation_onResolutionOverdue: "escalate" }
  )

  pure def withBranches(s: Settings, b: Branches): Settings = { ...s, escalation: { ...s.escalation, enabled: b.escalation_enabled, onResolutionOverdue: b.escalation_onResolutionOverdue } }

  pure val HOLD_REASONS_BY_OPERATOR: Set[str] = Set("third_party", "patrol", "no_data")

  pure val CLOSE_RESULT_IDS: Set[str] = Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass")

  pure val TYPICAL_PERMISSION_SETS: Set[Set[str]] = Set(Set("incident:claim", "incident:accept", "incident:hold", "incident:release", "incident:close", "incident:transfer:own", "incident:bulk", "incident:run_action", "agent:set_not_ready"), Set("incident:claim", "incident:accept", "incident:hold", "incident:release", "incident:close", "incident:close:unprocessed", "incident:reopen", "incident:transfer:own", "incident:transfer:any", "incident:reassign", "incident:bulk", "incident:run_action", "agent:set_not_ready"))

  pure val STEP_RESULT_IDS: Set[str] = Set("processed")

  pure val STEP_RESULT_CLOSE_IDS: Set[str] = Set("close")

  pure val EXIT_RULE: { appliesTo: Set[str], requiresAnyOf: Set[str], requiresAnyOfWithHoldLimit: Set[str], disables: Set[str] } = { appliesTo: Set("incident:claim", "incident:accept"), requiresAnyOf: Set("incident:hold", "incident:release", "incident:close"), requiresAnyOfWithHoldLimit: Set("incident:release", "incident:close"), disables: Set("incident:claim", "incident:accept") }

  pure val USED_PERMISSIONS: Set[str] = Set("agent:set_not_ready", "incident:accept", "incident:bulk", "incident:claim", "incident:close", "incident:close:unprocessed", "incident:hold", "incident:reassign", "incident:release", "incident:reopen", "incident:run_action", "incident:transfer:any", "incident:transfer:own")

  pure val TIMER_IDS: Set[str] = Set("reaction", "resolution", "hold")

  pure val NO_TIMER: Timer = { due: 0, paused: false, left: 0, fired: 0, since: 0 }

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, occurredAt: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "", eventGuid: "" }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

  pure val NO_FORM: Form = { targetId: "", primaryId: "", resultId: "", reasonId: "", causeId: "", comment: "" }

  pure val CAUSE_FOR: str -> str = Map("mass" -> "power")

  /* ===== Определения машины (cel.definitions) ===== */


  // §8.1. Адресат: владелец-человек, а пока группа не приняла — сама группа

  def addressee(x: Incident): str =
    (if ((x.owner != "")) x.owner else x.assignmentGroup)

  def unowned(x: Incident): bool =
    ((x.owner == "") and (x.assignmentGroup == ""))

  // §8.1, §10.1 (RULE-107). Кому форма «Передать» предлагает инцидент: не себе и не своей группе, не текущему адресату, тому, кто может принять, и не вышедшему, чья дежурная группа — своя: передача ему сразу ушла бы этой группе, то есть вернулась бы себе — как запрет «на себя» у автоэскалации (RULE-93)

  def offersTransferTo(who: str, t: str, x: Incident): bool =
    (((not(isSelf(who, t)) and (t != addressee(x))) and canAccept(t, x, "")) and not(((isOperator(t) and (agentState(t) == "offline")) and isSelf(who, dutyGroupOf(t)))))

  // §10.1. «Я» как адресат: сам оператор и дежурные группы, в которые он входит

  def isSelf(who: str, id: str): bool =
    ((id != "") and ((id == who) or (isGroup(id) and members(id).foldl(false, (acc, y1) => acc or y1 == who))))

  def isTarget(who: str, x: Incident): bool =
    isSelf(who, addressee(x))

  // §2.4. Отношение смотрящего к инциденту: ожидающий моего принятия — «мне адресован», даже если владельцем записан я (BUG-60)

  def ownership(who: str, x: Incident): str =
    (if (((x.state == "pending_acceptance") and isTarget(who, x))) "target" else (if ((x.owner == who)) "owner" else (if (isTarget(who, x)) "target" else "other")))

  // §10.2. Инциденты человека в состоянии, кроме одного — для лимитов; у привязанных владельца нет, в лимит они не входят

  def mineIn(xs: List[Incident], who: str, state: str, except: str): List[Incident] =
    xs.select(e_2 => (((e_2.state == state) and (e_2.owner == who)) and (e_2.id != except)))

  // Условие «отношение ко мне» в scopeRule: владелец — мой инцидент, адресат — адресованный мне

  def matchesOwnership(who: str, x: Incident, role: str): bool =
    (if ((role == "owner")) (x.owner == who) else (if ((role == "target")) isTarget(who, x) else (ownership(who, x) == role)))

  // §5. Область права own: выполнено хоть одно из scopeRule.own.anyOf

  def scopeOwn(who: str, x: Incident, r: ScopeRule): bool =
    r.own.anyOf.foldl(false, (acc, c_3) => acc or (if ((c_3.state != "")) (x.state == c_3.state) else ((c_3.ownership != "") and matchesOwnership(who, x, c_3.ownership))))

  // Категория состояния инцидента — одна из cats (stateCategories)

  def inCategory(x: Incident, cats: List[str]): bool =
    settings.states.foldl(false, (acc, s_4) => acc or ((s_4.id == x.state) and cats.foldl(false, (acc, y5) => acc or y5 == s_4.category)))

  // §11. Основной при «Взять в работу» на выборке, если его не назвал оператор: свой в работе, иначе новый; из них — самый срочный, у равных — появившийся раньше, у совсем равных — первый по порядку выборки: сервер передаёт её по возрастанию номера, а не в порядке отметки (строки в CEL и Quint не упорядочиваются). Списком из одного или пустым

  def mergePrimary(xs: List[Incident], who: str): List[Incident] =
    { val mine_6 = xs.select(e_7 => ((e_7.state == "in_progress") and (e_7.owner == who)))  { val c_8 = (if ((mine_6.length() > 0)) mine_6 else xs.select(e_9 => (e_9.state == "new")))  { val top_10 = c_8.select(e_11 => c_8.foldl(true, (acc, k_12) => acc and (k_12.priority <= e_11.priority)))  { val first_13 = top_10.select(e_14 => top_10.foldl(true, (acc, k_15) => acc and (e_14.occurredAt <= k_15.occurredAt)))  (if ((first_13.length() > 0)) [first_13[0]] else []) } } } }

  // §8.1, §12. Человек на месте: его состояние — не «только просмотр» (перерыв, вышел)

  def onDuty(who: str): bool =
    not(settings.session.states.foldl(false, (acc, s_16) => acc or ((s_16.id == agentState(who)) and s_16.readOnly)))

  // §9. Кто получит уведомление: человек или участники дежурной группы — на месте и с доступом к объекту инцидента

  def recipients(whom: str, x: Incident): List[str] =
    (if (isGroup(whom)) members(whom) else [whom]).select(m_17 => (onDuty(m_17) and access(m_17, x)))

  // Таймер идёт: дедлайн есть и ещё не сработал (на потолке эскалации реакции — уже сработал)

  def timerRuns(x: Incident, id: str): bool =
    ((x.timers.get(id).due != 0) and (x.timers.get(id).fired != x.timers.get(id).due))

  // Закрыт без результата или результатом полной обработки (finish)

  def closedFinished(x: Incident): bool =
    ((x.closeResultId == "") or settings.closeResults.foldl(false, (acc, i_18) => acc or ((i_18.id == x.closeResultId) and i_18.finish)))

  // §8.3. Адресован автоэскалацией: адресат — адресат текущего уровня. Уровень после ручной передачи остаётся (RULE-76), но адресат уже другой

  def escalatedTo(x: Incident): bool =
    ((x.escalationLevel > 0) and settings.escalation.levels.foldl(false, (acc, l_19) => acc or ((l_19.level == x.escalationLevel) and (l_19.target == addressee(x)))))

  def isDone(x: Incident): bool =
    settings.states.foldl(false, (acc, s_20) => acc or ((s_20.id == x.state) and (s_20.category == "done")))

  // §5, §7, ARCH-15. Закрыт «Ложной тревогой». Тревога ложная, когда так закрыты сам инцидент и все его соседи, видимые смотрящему (alarm.allFalseAlarm карточки). Определение — для сервера и бэкенда, переходы его не используют

  def closedFalseAlarm(x: Incident): bool =
    (isDone(x) and (x.closeResultId == "false_alarm"))

  // Инцидент по id — списком из одного или пустым

  def byId(xs: List[Incident], id: str): List[Incident] =
    xs.select(e_21 => (e_21.id == id))

  // §5, §8.1. Доступ к объекту: человеку — по его ролям, группе — хотя бы у одного участника

  def hasAccess(who: str, x: Incident): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_22) => acc or access(m_22, x)) else (isOperator(who) and access(who, x)))

  def canAcceptPerson(m: str, x: Incident): bool =
    (can(m, "incident:accept") and access(m, x))

  // §8.1. Может ли принять: право «Принимать» и доступ к объекту; группа — если хотя бы один участник, кроме except: у него инцидент уже есть (RULE-93)

  def canAccept(who: str, x: Incident, except: str): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_23) => acc or ((m_23 != except) and canAcceptPerson(m_23, x))) else canAcceptPerson(who, x))

  // §8.1. Дежурная группа человека — первая, в которую он входит

  def dutyGroupOf(who: str): str =
    { val gs_24 = dutyGroups.select(g_25 => members(g_25).foldl(false, (acc, y26) => acc or y26 == who))  (if ((gs_24.length() > 0)) gs_24[0] else "") }

  // §12.1. Человек вошёл в МИ: на месте или на перерыве, но не вышел (RULE-100)

  def signedIn(who: str): bool =
    (agentState(who) != "offline")

  // §8.3, RULE-100. Адресат уровня эскалации может принять сейчас: как canAccept, и принимающий не вышел из МИ; вышедшему человеку инцидент уйдёт его дежурной группе (addressee_signed_out_to_group) — уровень доступен, если в ней кто-то, кроме except, не вышел и может принять. Перерыв не мешает (§12.1)

  def canAcceptNow(who: str, x: Incident, except: str): bool =
    (if (isGroup(who)) members(who).foldl(false, (acc, m_27) => acc or (((m_27 != except) and signedIn(m_27)) and canAcceptPerson(m_27, x))) else (canAcceptPerson(who, x) and (signedIn(who) or { val g_28 = dutyGroupOf(who)  ((g_28 != "") and members(g_28).foldl(false, (acc, m_29) => acc or ((((m_29 != except) and (m_29 != who)) and signedIn(m_29)) and canAcceptPerson(m_29, x)))) })))

  // §8.3. Уровни автоэскалации выше текущего и не выше потолка, адресат которых может принять сейчас (canAcceptNow, RULE-100); уровень, где принять может только тот, у кого инцидент уже есть, пропускается (RULE-93)

  def nextLevels(x: Incident): List[Level] =
    settings.escalation.levels.select(l_30 => ((((l_30.level > x.escalationLevel) and (l_30.level <= settings.escalation.maxLevel)) and (l_30.target != addressee(x))) and canAcceptNow(l_30.target, x, x.owner)))

  // §2.2. Результаты закрытия, которые этот оператор может выбрать для инцидента

  def closeOptions(who: str, x: Incident, surface: str): List[CloseResultItem] =
    settings.closeResults.select(i_31 => (((can(who, i_31.permission) and i_31.fromStates.foldl(false, (acc, y32) => acc or y32 == x.state)) and not((i_31.ownerOnlyInStates.foldl(false, (acc, y33) => acc or y33 == x.state) and (x.owner != who)))) and (((surface == "") or (i_31.surfaces.length() == 0)) or i_31.surfaces.foldl(false, (acc, y34) => acc or y34 == surface))))

  def stepsOk(i: CloseResultItem, x: Incident): bool =
    ((i.requiredStepSet == "none") or stepsFilled(x, i.requiredStepSet))

  // Адресат, если это человек, иначе пусто: так в owner попадает только человек

  def personOf(id: str): str =
    (if (((id != "") and not(isGroup(id)))) id else "")

  // Адресат, если это дежурная группа, иначе пусто: так группа попадает в assignmentGroup

  def groupOf(id: str): str =
    (if (((id != "") and isGroup(id))) id else "")

  // §8.3. Уровень, на который уходит инцидент: ближайший из nextLevels — списком из одного или пустым

  def levelUp(x: Incident): List[Level] =
    { val ls_35 = nextLevels(x)  ls_35.select(l_36 => ls_35.foldl(true, (acc, k_37) => acc and (l_36.level <= k_37.level))) }

  def levelUpTarget(x: Incident): str =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].target else "")

  def levelUpNumber(x: Incident): int =
    (if ((levelUp(x).length() > 0)) levelUp(x)[0].level else 0)

  def timerDef(id: str): TimerDef =
    settings.timerDefs.select(t_38 => (t_38.id == id))[0]

  // Сколько условий у строки overrides: чем больше, тем строка специфичнее

  def overrideKeys(o: Override): int =
    (((o.eventType.length() + o.priority.length()) + o.sourceGroup.length()) + o.scenario.length())

  // §4, правило 2. Старшинство строки уточнения: сначала число условий, при равном числе строка со сценарием старше (решение 2026-10-28)

  def overrideRank(o: Override): int =
    ((overrideKeys(o) * 2) + o.scenario.length())

  def overrideMatches(x: Incident, o: Override): bool =
    (((((o.eventType.length() == 0) or (o.eventType[0] == x.eventType)) and ((o.priority.length() == 0) or (o.priority[0] == x.priority))) and ((o.sourceGroup.length() == 0) or inSourceGroup(x, o.sourceGroup[0]))) and ((o.scenario.length() == 0) or (o.scenario[0] == x.scenario)))

  // §4, правило 2. Строка уточнения учитывается, только если все её признаки — из overridesBy таймера (ARCH-11)

  def overrideAllowed(t: TimerDef, o: Override): bool =
    (((((o.eventType.length() == 0) or t.overridesBy.foldl(false, (acc, y39) => acc or y39 == "eventType")) and ((o.priority.length() == 0) or t.overridesBy.foldl(false, (acc, y40) => acc or y40 == "priority"))) and ((o.sourceGroup.length() == 0) or t.overridesBy.foldl(false, (acc, y41) => acc or y41 == "sourceGroup"))) and ((o.scenario.length() == 0) or t.overridesBy.foldl(false, (acc, y42) => acc or y42 == "scenario")))

  // §4, правило 2. Норматив, с: самая специфичная строка overrides (больше условий; при равном числе — со сценарием; при равных и этом — первая), иначе byPriority, иначе defaultSec

  def norm(x: Incident, t: TimerDef): int =
    { val ms_43 = t.overrides.select(o_44 => (overrideAllowed(t, o_44) and overrideMatches(x, o_44)))  (if ((ms_43.length() > 0)) ms_43.select(o_45 => ms_43.foldl(true, (acc, k_46) => acc and (overrideRank(k_46) <= overrideRank(o_45))))[0].sec else (if (t.byPriority.keys().contains(x.priority)) t.byPriority.get(x.priority) else t.defaultSec)) }

  // §4. Срок удержания, с — по причине (secFrom таймера hold). У причины с deadlineFromIdle («Нет связи») — порог возврата в очередь минус порог удержания, не меньше 0: срок причины и возврат по молчанию совпадают при любых порогах (RULE-118, RULE-129, RULE-132). Причины нет — -1, срок не ставится. Срок у причины обязателен, кроме deadlineFromIdle (§4, правило 7; RULE-135, check_machine.py): ветка «maxMinutes пуст» — подстраховка

  def holdSec(x: Incident): int =
    { val rs_47 = settings.holdReasons.select(r_48 => (r_48.id == x.holdReasonId))  (if ((rs_47.length() == 0)) (0 - 1) else (if (rs_47[0].deadlineFromIdle) (if ((settings.session.idleReleaseSec > settings.session.idleHoldSec)) (settings.session.idleReleaseSec - settings.session.idleHoldSec) else 0) else (if ((rs_47[0].maxMinutes.length() > 0)) (rs_47[0].maxMinutes[0] * 60) else (0 - 1)))) }

  // §8.3. Норматив реакции уровня автоэскалации: уровня нет — последний; уровень 0 — обычный норматив (RULE-76)

  def levelNorm(x: Incident): int =
    (if (((x.escalationLevel > 0) and (settings.escalation.levels.length() > 0))) { val ls_49 = settings.escalation.levels.select(l_50 => (l_50.level == x.escalationLevel))  (if ((ls_49.length() > 0)) ls_49[0].reactionSec else settings.escalation.levels[(settings.escalation.levels.length() - 1)].reactionSec) } else norm(x, timerDef("reaction")))

  // §4. Длительность таймера, с: из справочника (secFrom), по уровню эскалации или по нормативам

  def timerSec(x: Incident, id: str, mode: str): int =
    (if ((timerDef(id).secFrom != "")) holdSec(x) else (if ((mode == "byEscalationLevel")) levelNorm(x) else norm(x, timerDef(id))))

  // Остаток таймера, мс: идёт — до дедлайна, на паузе — остаток, не запускался — -1

  def leftOf(x: Incident, id: str, now: int): int =
    { val t_51 = x.timers.get(id)  (if ((t_51.due != 0)) (if (((t_51.due - now) > 0)) (t_51.due - now) else 0) else (if (t_51.paused) t_51.left else (0 - 1))) }

  // RULE-50. Норматив нарушен и отработан: остатка нет, дедлайн сработал

  def spent(x: Incident, id: str, now: int): bool =
    ((leftOf(x, id, now) == 0) and (x.timers.get(id).fired != 0))

  // §11.4, BUG-73, BUG-75. Был в группе основного p в момент at: открытый привязанный, присоединённый не позже, или вышедший не раньше

  def inGroupAt(e: Incident, p: Incident, at: int): bool =
    ((((e.linkedTo == p.id) and not(isDone(e))) and (e.linkedAt <= at)) or (((e.leftGroup.primaryId == p.id) and (e.leftGroup.linkedAt <= at)) and (e.leftGroup.at >= at)))

  // §14.5, ARCH-15. Условие правила подошло событию: каждое заданное поле совпало (поля условия соединены «и»); группа — устройство-источник в ней или во вложенной

  def conditionMatches(c: Condition, e: Event): bool =
    (((((c.eventType.length() == 0) or (c.eventType[0] == e.eventType)) and ((c.device.length() == 0) or (c.device[0] == e.device))) and ((c.deviceType.length() == 0) or (c.deviceType[0] == e.deviceType))) and ((c.group.length() == 0) or deviceInGroup(e.device, c.group[0])))

  // §14.5, ARCH-15. Точность условия — по самому точному его полю: устройство 3000, тип устройства 2000, группа 1000 плюс глубина группы в дереве; только тип события — 0 (тип ранга не добавляет)

  def conditionRank(c: Condition): int =
    (if ((c.device.length() > 0)) 3000 else (if ((c.deviceType.length() > 0)) 2000 else (if ((c.group.length() > 0)) (1000 + groupDepth(c.group[0])) else 0)))

  // §14.5, ARCH-15. Точность правила для события — наибольшая из подошедших условий (условия соединены «или»); не подошло ни одно — -1

  def ruleRank(r: Rule, e: Event): int =
    { val ks_52 = r.conditions.select(c_53 => conditionMatches(c_53, e)).foldl([], (acc, c_54) => acc.append(conditionRank(c_54)))  (if ((ks_52.length() == 0)) (0 - 1) else ks_52.select(k_55 => ks_52.foldl(true, (acc, j_56) => acc and (j_56 <= k_55)))[0]) }

  // §14.5, ARCH-15. Правило подошло событию: у него есть сценарий и подошло хоть одно условие. Правило без сценария в выборе не участвует

  def ruleMatches(r: Rule, e: Event): bool =
    ((r.scenarios.length() > 0) and r.conditions.foldl(false, (acc, c_57) => acc or conditionMatches(c_57, e)))

  // §14.5, ARCH-15 (решение пользователя 2026-10-28). Правило a старше b для события — строго: точнее условие; при равной точности — выше приоритет; при равном приоритете — раньше создано. Полное равенство — ни одно не старше: решает порядок списка правил

  def ruleBeats(a: Rule, b: Rule, e: Event): bool =
    { val ra_58 = ruleRank(a, e)  { val rb_59 = ruleRank(b, e)  ((ra_58 > rb_59) or ((ra_58 == rb_59) and ((a.priority > b.priority) or ((a.priority == b.priority) and (a.createdAt < b.createdAt))))) } }

  // §14.5, ARCH-15. Правило-победитель сценария s для события: из подошедших правил с этим сценарием — те, кого не старше ни одно; сервер берёт первое по порядку списка. От него приоритет и ruleGuid инцидента

  def ruleFor(rules: List[Rule], e: Event, s: str): List[Rule] =
    { val ms_60 = rules.select(r_61 => (ruleMatches(r_61, e) and r_61.scenarios.foldl(false, (acc, y62) => acc or y62 == s)))  ms_60.select(r_63 => not(ms_60.foldl(false, (acc, o_64) => acc or ruleBeats(o_64, r_63, e)))) }

  // Инцидент по id — списком из одного или пустым

  def incidentById(incidents: List[Incident], id: str): List[Incident] =
    byId(incidents, id)

  // §11. Привязанные к основному id — и открытые, и закрытые вместе с ним

  def linkedOf(incidents: List[Incident], id: str): List[Incident] =
    incidents.select(e_65 => (e_65.linkedTo == id))

  // §10.2. Сколько инцидентов человека в состоянии, кроме одного — для лимитов

  def countMine(incidents: List[Incident], who: str, state: str, except: str): int =
    mineIn(incidents, who, state, except).length()

  // §10.2. Те же инциденты списком — для подсказки, кто держит лимит

  def mineOf(incidents: List[Incident], who: str, state: str, except: str): List[Incident] =
    mineIn(incidents, who, state, except)

  // §11.4. Кто был в группе основного p в момент at (inGroupAt)

  def groupMembersAt(incidents: List[Incident], p: Incident, at: int): List[Incident] =
    incidents.select(e_66 => ((e_66.id != p.id) and inGroupAt(e_66, p, at)))

  // §14.5, ARCH-15. Соседи — инциденты того же события, кроме самого x: другие службы той же тревоги. Не привязка §11: у каждого свой владелец, сроки и закрытие

  def siblingsOf(incidents: List[Incident], x: Incident): List[Incident] =
    incidents.select(s_67 => (((x.eventGuid != "") and (s_67.eventGuid == x.eventGuid)) and (s_67.id != x.id)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w68 = if (not(timerDef(timerId).pausable)) {
      val sec_69 = timerSec(w0.inc.get(iid), timerId, "")
      val w70 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_69 < 0)) 0 else (c.now + (sec_69 * 1000))) }) }) }
      val w71 = { ...w70, inc: w70.inc.set(iid, { ...w70.inc.get(iid), timers: w70.inc.get(iid).timers.set(timerId, { ...w70.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w71
    } else {
      val w72 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_73 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w74 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_73 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_73)) }) }) }
      val w75 = { ...w74, inc: w74.inc.set(iid, { ...w74.inc.get(iid), timers: w74.inc.get(iid).timers.set(timerId, { ...w74.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w76 = { ...w75, inc: w75.inc.set(iid, { ...w75.inc.get(iid), timers: w75.inc.get(iid).timers.set(timerId, { ...w75.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w76
    } else w0
      w72
    }
    w68
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w77 = if (not(timerDef(timerId).pausable)) {
      val w78 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w79 = { ...w78, inc: w78.inc.set(iid, { ...w78.inc.get(iid), timers: w78.inc.get(iid).timers.set(timerId, { ...w78.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w79
    } else {
      val w80 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w81 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w82 = { ...w81, inc: w81.inc.set(iid, { ...w81.inc.get(iid), timers: w81.inc.get(iid).timers.set(timerId, { ...w81.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w83 = { ...w82, inc: w82.inc.set(iid, { ...w82.inc.get(iid), timers: w82.inc.get(iid).timers.set(timerId, { ...w82.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w83
    } else w0
      w80
    }
    w77
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_84 = ""
    val w85 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_84 }) }
    w85
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_86 = ""
    val w87 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_86 }) }
    w87
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_88 = 0
    val w89 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_88 }) }
    w89
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w90 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w91 = if (timerDef("reaction").startsOnce) {
      val w92 = ec_resumeTimer(w0, c, iid, "reaction")
      w92
    } else {
      val w93 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w94 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w95 = { ...w94, inc: w94.inc.set(iid, { ...w94.inc.get(iid), timers: w94.inc.get(iid).timers.set("reaction", { ...w94.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w96 = { ...w95, inc: w95.inc.set(iid, { ...w95.inc.get(iid), timers: w95.inc.get(iid).timers.set("reaction", { ...w95.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w96
    } else {
      val sec_97 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w98 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_97 < 0)) 0 else (c.now + (sec_97 * 1000))) }) }) }
      val w99 = { ...w98, inc: w98.inc.set(iid, { ...w98.inc.get(iid), timers: w98.inc.get(iid).timers.set("reaction", { ...w98.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w100 = { ...w99, inc: w99.inc.set(iid, { ...w99.inc.get(iid), timers: w99.inc.get(iid).timers.set("reaction", { ...w99.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w101 = { ...w100, inc: w100.inc.set(iid, { ...w100.inc.get(iid), timers: w100.inc.get(iid).timers.set("reaction", { ...w100.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w101
    }
      w93
    }
      w91
    }
    w90
  }

  def e_create_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_create(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_create_0(ws, c1, iid)
    val w2 = e_create_1(w1, c1, iid)
    val w3 = e_create_2(w2, c1, iid)
    val w4 = e_create_3(w3, c1, iid)
    val w5 = e_create_4(w4, c1, iid)
    w5
  }

  // claim: manual → in_progress

  def ok_claim(c: Ctx, iid: str): bool = all {
    Set("new").contains(world.inc.get(iid).state),
    can(c.me, "incident:claim"),
    not(settings.session.states.foldl(false, (acc, s_102) => acc or ((s_102.id == agentState(c.me)) and s_102.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_103 = c.actor
    val w104 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_103 }) }
    w104
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w105 = if (timerDef("reaction").startsOnce) {
      val w106 = ec_pauseTimer(w0, c, iid, "reaction")
      w106
    } else {
      val w107 = if (false) {
      val w108 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w109 = { ...w108, inc: w108.inc.set(iid, { ...w108.inc.get(iid), timers: w108.inc.get(iid).timers.set("reaction", { ...w108.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w110 = { ...w109, inc: w109.inc.set(iid, { ...w109.inc.get(iid), timers: w109.inc.get(iid).timers.set("reaction", { ...w109.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w111 = { ...w110, inc: w110.inc.set(iid, { ...w110.inc.get(iid), timers: w110.inc.get(iid).timers.set("reaction", { ...w110.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w111
    } else {
      val w112 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_113 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w114 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_113) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w115 = { ...w114, inc: w114.inc.set(iid, { ...w114.inc.get(iid), timers: w114.inc.get(iid).timers.set("reaction", { ...w114.inc.get(iid).timers.get("reaction"), paused: keep_113 }) }) }
      val w116 = { ...w115, inc: w115.inc.set(iid, { ...w115.inc.get(iid), timers: w115.inc.get(iid).timers.set("reaction", { ...w115.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w117 = { ...w116, inc: w116.inc.set(iid, { ...w116.inc.get(iid), timers: w116.inc.get(iid).timers.set("reaction", { ...w116.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w117
    }
      w112
    }
      w107
    }
    w105
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w118 = if (not(timerDef("resolution").pausable)) {
      val sec_119 = timerSec(w0.inc.get(iid), "resolution", "")
      val w120 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_119 < 0)) 0 else (c.now + (sec_119 * 1000))) }) }) }
      val w121 = { ...w120, inc: w120.inc.set(iid, { ...w120.inc.get(iid), timers: w120.inc.get(iid).timers.set("resolution", { ...w120.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w121
    } else {
      val w122 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_123 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w124 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_123 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_123)) }) }) }
      val w125 = { ...w124, inc: w124.inc.set(iid, { ...w124.inc.get(iid), timers: w124.inc.get(iid).timers.set("resolution", { ...w124.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w126 = { ...w125, inc: w125.inc.set(iid, { ...w125.inc.get(iid), timers: w125.inc.get(iid).timers.set("resolution", { ...w125.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w126
    } else w0
      w122
    }
    w118
  }

  def e_claim_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_claim_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_claim(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_claim_0(ws, c1, iid)
    val w2 = e_claim_1(w1, c1, iid)
    val w3 = e_claim_2(w2, c1, iid)
    val w4 = e_claim_3(w3, c1, iid)
    val w5 = e_claim_4(w4, c1, iid)
    w5
  }

  // accept: manual → in_progress

  def ok_accept(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    can(c.me, "incident:accept"),
    isTarget(c.me, world.inc.get(iid)),
    not(settings.session.states.foldl(false, (acc, s_127) => acc or ((s_127.id == agentState(c.me)) and s_127.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_128 = c.actor
    val w129 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_128 }) }
    w129
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_130 = ""
    val w131 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_130 }) }
    w131
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w132 = if (timerDef("reaction").startsOnce) {
      val w133 = ec_pauseTimer(w0, c, iid, "reaction")
      w133
    } else {
      val w134 = if (false) {
      val w135 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w136 = { ...w135, inc: w135.inc.set(iid, { ...w135.inc.get(iid), timers: w135.inc.get(iid).timers.set("reaction", { ...w135.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w137 = { ...w136, inc: w136.inc.set(iid, { ...w136.inc.get(iid), timers: w136.inc.get(iid).timers.set("reaction", { ...w136.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w138 = { ...w137, inc: w137.inc.set(iid, { ...w137.inc.get(iid), timers: w137.inc.get(iid).timers.set("reaction", { ...w137.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w138
    } else {
      val w139 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_140 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w141 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_140) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w142 = { ...w141, inc: w141.inc.set(iid, { ...w141.inc.get(iid), timers: w141.inc.get(iid).timers.set("reaction", { ...w141.inc.get(iid).timers.get("reaction"), paused: keep_140 }) }) }
      val w143 = { ...w142, inc: w142.inc.set(iid, { ...w142.inc.get(iid), timers: w142.inc.get(iid).timers.set("reaction", { ...w142.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w144 = { ...w143, inc: w143.inc.set(iid, { ...w143.inc.get(iid), timers: w143.inc.get(iid).timers.set("reaction", { ...w143.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w144
    }
      w139
    }
      w134
    }
    w132
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w145 = if (not(timerDef("resolution").pausable)) {
      val sec_146 = timerSec(w0.inc.get(iid), "resolution", "")
      val w147 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_146 < 0)) 0 else (c.now + (sec_146 * 1000))) }) }) }
      val w148 = { ...w147, inc: w147.inc.set(iid, { ...w147.inc.get(iid), timers: w147.inc.get(iid).timers.set("resolution", { ...w147.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w148
    } else {
      val w149 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_150 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w151 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_150 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_150)) }) }) }
      val w152 = { ...w151, inc: w151.inc.set(iid, { ...w151.inc.get(iid), timers: w151.inc.get(iid).timers.set("resolution", { ...w151.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w153 = { ...w152, inc: w152.inc.set(iid, { ...w152.inc.get(iid), timers: w152.inc.get(iid).timers.set("resolution", { ...w152.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w153
    } else w0
      w149
    }
    w145
  }

  def e_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_accept_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_accept(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_accept_0(ws, c1, iid)
    val w2 = e_accept_1(w1, c1, iid)
    val w3 = e_accept_2(w2, c1, iid)
    val w4 = e_accept_3(w3, c1, iid)
    val w5 = e_accept_4(w4, c1, iid)
    val w6 = e_accept_5(w5, c1, iid)
    w6
  }

  // reject: manual → new

  def ok_reject(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    can(c.me, "incident:release"),
    isTarget(c.me, world.inc.get(iid)),
    not(settings.session.states.foldl(false, (acc, s_154) => acc or ((s_154.id == agentState(c.me)) and s_154.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_155 = ""
    val w156 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_155 }) }
    w156
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_157 = ""
    val w158 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_157 }) }
    w158
  }

  def e_reject_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_reject(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_reject_0(ws, c1, iid)
    val w2 = e_reject_1(w1, c1, iid)
    val w3 = e_reject_2(w2, c1, iid)
    w3
  }

  // hold: manual → on_hold

  def ok_hold(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    can(c.me, "incident:hold"),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_159) => acc or ((s_159.id == agentState(c.me)) and s_159.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_160 = c.form.reasonId
    val w161 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_160 }) }
    w161
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w162 = if (not(timerDef("resolution").pausable)) {
      val w163 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w164 = { ...w163, inc: w163.inc.set(iid, { ...w163.inc.get(iid), timers: w163.inc.get(iid).timers.set("resolution", { ...w163.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w164
    } else {
      val w165 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w166 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w167 = { ...w166, inc: w166.inc.set(iid, { ...w166.inc.get(iid), timers: w166.inc.get(iid).timers.set("resolution", { ...w166.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w168 = { ...w167, inc: w167.inc.set(iid, { ...w167.inc.get(iid), timers: w167.inc.get(iid).timers.set("resolution", { ...w167.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w168
    } else w0
      w165
    }
    w162
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w169 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w170 = if (timerDef("hold").startsOnce) {
      val w171 = ec_resumeTimer(w0, c, iid, "hold")
      w171
    } else {
      val w172 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w173 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w174 = { ...w173, inc: w173.inc.set(iid, { ...w173.inc.get(iid), timers: w173.inc.get(iid).timers.set("hold", { ...w173.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w175 = { ...w174, inc: w174.inc.set(iid, { ...w174.inc.get(iid), timers: w174.inc.get(iid).timers.set("hold", { ...w174.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w175
    } else {
      val sec_176 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w177 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_176 < 0)) 0 else (c.now + (sec_176 * 1000))) }) }) }
      val w178 = { ...w177, inc: w177.inc.set(iid, { ...w177.inc.get(iid), timers: w177.inc.get(iid).timers.set("hold", { ...w177.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w179 = { ...w178, inc: w178.inc.set(iid, { ...w178.inc.get(iid), timers: w178.inc.get(iid).timers.set("hold", { ...w178.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w180 = { ...w179, inc: w179.inc.set(iid, { ...w179.inc.get(iid), timers: w179.inc.get(iid).timers.set("hold", { ...w179.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w180
    }
      w172
    }
      w170
    }
    w169
  }

  def e_hold_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_hold(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "on_hold" }) }
    val w1 = e_hold_0(ws, c1, iid)
    val w2 = e_hold_1(w1, c1, iid)
    val w3 = e_hold_2(w2, c1, iid)
    val w4 = e_hold_3(w3, c1, iid)
    val w5 = e_hold_4(w4, c1, iid)
    w5
  }

  // resume: manual → in_progress

  def ok_resume(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:claim"),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_181) => acc or ((s_181.id == agentState(c.me)) and s_181.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w182 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w182
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w183 = if (timerDef("hold").startsOnce) {
      val w184 = ec_pauseTimer(w0, c, iid, "hold")
      w184
    } else {
      val w185 = if (false) {
      val w186 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w187 = { ...w186, inc: w186.inc.set(iid, { ...w186.inc.get(iid), timers: w186.inc.get(iid).timers.set("hold", { ...w186.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w188 = { ...w187, inc: w187.inc.set(iid, { ...w187.inc.get(iid), timers: w187.inc.get(iid).timers.set("hold", { ...w187.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w189 = { ...w188, inc: w188.inc.set(iid, { ...w188.inc.get(iid), timers: w188.inc.get(iid).timers.set("hold", { ...w188.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w189
    } else {
      val w190 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_191 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w192 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_191) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w193 = { ...w192, inc: w192.inc.set(iid, { ...w192.inc.get(iid), timers: w192.inc.get(iid).timers.set("hold", { ...w192.inc.get(iid).timers.get("hold"), paused: keep_191 }) }) }
      val w194 = { ...w193, inc: w193.inc.set(iid, { ...w193.inc.get(iid), timers: w193.inc.get(iid).timers.set("hold", { ...w193.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w195 = { ...w194, inc: w194.inc.set(iid, { ...w194.inc.get(iid), timers: w194.inc.get(iid).timers.set("hold", { ...w194.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w195
    }
      w190
    }
      w185
    }
    w183
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w196 = if (not(timerDef("resolution").pausable)) {
      val sec_197 = timerSec(w0.inc.get(iid), "resolution", "")
      val w198 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_197 < 0)) 0 else (c.now + (sec_197 * 1000))) }) }) }
      val w199 = { ...w198, inc: w198.inc.set(iid, { ...w198.inc.get(iid), timers: w198.inc.get(iid).timers.set("resolution", { ...w198.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w199
    } else {
      val w200 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_201 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w202 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_201 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_201)) }) }) }
      val w203 = { ...w202, inc: w202.inc.set(iid, { ...w202.inc.get(iid), timers: w202.inc.get(iid).timers.set("resolution", { ...w202.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w204 = { ...w203, inc: w203.inc.set(iid, { ...w203.inc.get(iid), timers: w203.inc.get(iid).timers.set("resolution", { ...w203.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w204
    } else w0
      w200
    }
    w196
  }

  def e_resume_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resume_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_resume(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_resume_0(ws, c1, iid)
    val w2 = e_resume_1(w1, c1, iid)
    val w3 = e_resume_2(w2, c1, iid)
    val w4 = e_resume_3(w3, c1, iid)
    val w5 = e_resume_4(w4, c1, iid)
    w5
  }

  // release: manual → new

  def ok_release(c: Ctx, iid: str): bool = all {
    Set("in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:release"),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_205) => acc or ((s_205.id == agentState(c.me)) and s_205.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_206 = ""
    val w207 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_206 }) }
    w207
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w208 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w208
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w209 = if (not(timerDef("resolution").pausable)) {
      val w210 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w211 = { ...w210, inc: w210.inc.set(iid, { ...w210.inc.get(iid), timers: w210.inc.get(iid).timers.set("resolution", { ...w210.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w211
    } else {
      val w212 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w213 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w214 = { ...w213, inc: w213.inc.set(iid, { ...w213.inc.get(iid), timers: w213.inc.get(iid).timers.set("resolution", { ...w213.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w215 = { ...w214, inc: w214.inc.set(iid, { ...w214.inc.get(iid), timers: w214.inc.get(iid).timers.set("resolution", { ...w214.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w215
    } else w0
      w212
    }
    w209
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w216 = if (timerDef("hold").startsOnce) {
      val w217 = ec_pauseTimer(w0, c, iid, "hold")
      w217
    } else {
      val w218 = if (false) {
      val w219 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w220 = { ...w219, inc: w219.inc.set(iid, { ...w219.inc.get(iid), timers: w219.inc.get(iid).timers.set("hold", { ...w219.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w221 = { ...w220, inc: w220.inc.set(iid, { ...w220.inc.get(iid), timers: w220.inc.get(iid).timers.set("hold", { ...w220.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w222 = { ...w221, inc: w221.inc.set(iid, { ...w221.inc.get(iid), timers: w221.inc.get(iid).timers.set("hold", { ...w221.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w222
    } else {
      val w223 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_224 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w225 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_224) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w226 = { ...w225, inc: w225.inc.set(iid, { ...w225.inc.get(iid), timers: w225.inc.get(iid).timers.set("hold", { ...w225.inc.get(iid).timers.get("hold"), paused: keep_224 }) }) }
      val w227 = { ...w226, inc: w226.inc.set(iid, { ...w226.inc.get(iid), timers: w226.inc.get(iid).timers.set("hold", { ...w226.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w228 = { ...w227, inc: w227.inc.set(iid, { ...w227.inc.get(iid), timers: w227.inc.get(iid).timers.set("hold", { ...w227.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w228
    }
      w223
    }
      w218
    }
    w216
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w229 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w230 = if (timerDef("reaction").startsOnce) {
      val w231 = ec_resumeTimer(w0, c, iid, "reaction")
      w231
    } else {
      val w232 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w233 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w234 = { ...w233, inc: w233.inc.set(iid, { ...w233.inc.get(iid), timers: w233.inc.get(iid).timers.set("reaction", { ...w233.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w235 = { ...w234, inc: w234.inc.set(iid, { ...w234.inc.get(iid), timers: w234.inc.get(iid).timers.set("reaction", { ...w234.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w235
    } else {
      val sec_236 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w237 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_236 < 0)) 0 else (c.now + (sec_236 * 1000))) }) }) }
      val w238 = { ...w237, inc: w237.inc.set(iid, { ...w237.inc.get(iid), timers: w237.inc.get(iid).timers.set("reaction", { ...w237.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w239 = { ...w238, inc: w238.inc.set(iid, { ...w238.inc.get(iid), timers: w238.inc.get(iid).timers.set("reaction", { ...w238.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w240 = { ...w239, inc: w239.inc.set(iid, { ...w239.inc.get(iid), timers: w239.inc.get(iid).timers.set("reaction", { ...w239.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w240
    }
      w232
    }
      w230
    }
    w229
  }

  def e_release_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_release_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_release(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_release_0(ws, c1, iid)
    val w2 = e_release_1(w1, c1, iid)
    val w3 = e_release_2(w2, c1, iid)
    val w4 = e_release_3(w3, c1, iid)
    val w5 = e_release_4(w4, c1, iid)
    val w6 = e_release_5(w5, c1, iid)
    val w7 = e_release_6(w6, c1, iid)
    w7
  }

  // transfer: manual → pending_acceptance

  def ok_transfer(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, (if (scopeOwn(c.me, world.inc.get(iid), { own: { anyOf: [{ state: "new", ownership: "" }, { state: "", ownership: "owner" }, { state: "", ownership: "target" }] } })) "incident:transfer:own" else "incident:transfer:any")),
    not(settings.session.states.foldl(false, (acc, s_241) => acc or ((s_241.id == agentState(c.me)) and s_241.readOnly))),
    transferTargets.foldl(false, (acc, t_242) => acc or (offersTransferTo(c.me, t_242, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_243) => acc and (isDone(e_243) or hasAccess(t_242, e_243))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_244) => acc and (isDone(e_244) or hasAccess(c.form.targetId, e_244)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_245 = personOf(c.form.targetId)
    val w246 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_245 }) }
    w246
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_247 = groupOf(c.form.targetId)
    val w248 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_247 }) }
    w248
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w249 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w249
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w250 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w250
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w251 = if (not(timerDef("resolution").pausable)) {
      val w252 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w253 = { ...w252, inc: w252.inc.set(iid, { ...w252.inc.get(iid), timers: w252.inc.get(iid).timers.set("resolution", { ...w252.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w253
    } else {
      val w254 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w255 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w256 = { ...w255, inc: w255.inc.set(iid, { ...w255.inc.get(iid), timers: w255.inc.get(iid).timers.set("resolution", { ...w255.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w257 = { ...w256, inc: w256.inc.set(iid, { ...w256.inc.get(iid), timers: w256.inc.get(iid).timers.set("resolution", { ...w256.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w257
    } else w0
      w254
    }
    w251
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w258 = if (timerDef("hold").startsOnce) {
      val w259 = ec_pauseTimer(w0, c, iid, "hold")
      w259
    } else {
      val w260 = if (false) {
      val w261 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w262 = { ...w261, inc: w261.inc.set(iid, { ...w261.inc.get(iid), timers: w261.inc.get(iid).timers.set("hold", { ...w261.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w263 = { ...w262, inc: w262.inc.set(iid, { ...w262.inc.get(iid), timers: w262.inc.get(iid).timers.set("hold", { ...w262.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w264 = { ...w263, inc: w263.inc.set(iid, { ...w263.inc.get(iid), timers: w263.inc.get(iid).timers.set("hold", { ...w263.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w264
    } else {
      val w265 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_266 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w267 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_266) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w268 = { ...w267, inc: w267.inc.set(iid, { ...w267.inc.get(iid), timers: w267.inc.get(iid).timers.set("hold", { ...w267.inc.get(iid).timers.get("hold"), paused: keep_266 }) }) }
      val w269 = { ...w268, inc: w268.inc.set(iid, { ...w268.inc.get(iid), timers: w268.inc.get(iid).timers.set("hold", { ...w268.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w270 = { ...w269, inc: w269.inc.set(iid, { ...w269.inc.get(iid), timers: w269.inc.get(iid).timers.set("hold", { ...w269.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w270
    }
      w265
    }
      w260
    }
    w258
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w271 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w272 = if (timerDef("reaction").startsOnce) {
      val w273 = ec_resumeTimer(w0, c, iid, "reaction")
      w273
    } else {
      val w274 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w275 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w276 = { ...w275, inc: w275.inc.set(iid, { ...w275.inc.get(iid), timers: w275.inc.get(iid).timers.set("reaction", { ...w275.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w277 = { ...w276, inc: w276.inc.set(iid, { ...w276.inc.get(iid), timers: w276.inc.get(iid).timers.set("reaction", { ...w276.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w277
    } else {
      val sec_278 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w279 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_278 < 0)) 0 else (c.now + (sec_278 * 1000))) }) }) }
      val w280 = { ...w279, inc: w279.inc.set(iid, { ...w279.inc.get(iid), timers: w279.inc.get(iid).timers.set("reaction", { ...w279.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w281 = { ...w280, inc: w280.inc.set(iid, { ...w280.inc.get(iid), timers: w280.inc.get(iid).timers.set("reaction", { ...w280.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w282 = { ...w281, inc: w281.inc.set(iid, { ...w281.inc.get(iid), timers: w281.inc.get(iid).timers.set("reaction", { ...w281.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w282
    }
      w274
    }
      w272
    }
    w271
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_283 = c.before.owner
    val w284 = if (((whom_283 != "") and (whom_283 != c.actor))) w0 else w0
    w284
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_285 = addressee(w0.inc.get(iid))
    val w286 = if (((whom_285 != "") and (whom_285 != c.actor))) w0 else w0
    w286
  }

  def apply_transfer(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "pending_acceptance" }) }
    val w1 = e_transfer_0(ws, c1, iid)
    val w2 = e_transfer_1(w1, c1, iid)
    val w3 = e_transfer_2(w2, c1, iid)
    val w4 = e_transfer_3(w3, c1, iid)
    val w5 = e_transfer_4(w4, c1, iid)
    val w6 = e_transfer_5(w5, c1, iid)
    val w7 = e_transfer_6(w6, c1, iid)
    val w8 = e_transfer_7(w7, c1, iid)
    val w9 = e_transfer_8(w8, c1, iid)
    val w10 = e_transfer_9(w9, c1, iid)
    val w11 = e_transfer_10(w10, c1, iid)
    w11
  }

  // takeover: manual → in_progress

  def ok_takeover(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:reassign"),
    can(c.me, "incident:claim"),
    (ownership(c.me, world.inc.get(iid)) != "owner"),
    (ownership(c.me, world.inc.get(iid)) != "target"),
    not(settings.session.states.foldl(false, (acc, s_287) => acc or ((s_287.id == agentState(c.me)) and s_287.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_288 = c.actor
    val w289 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_288 }) }
    w289
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_290 = ""
    val w291 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_290 }) }
    w291
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w292 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w292
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w293 = if (timerDef("reaction").startsOnce) {
      val w294 = ec_pauseTimer(w0, c, iid, "reaction")
      w294
    } else {
      val w295 = if (false) {
      val w296 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w297 = { ...w296, inc: w296.inc.set(iid, { ...w296.inc.get(iid), timers: w296.inc.get(iid).timers.set("reaction", { ...w296.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w298 = { ...w297, inc: w297.inc.set(iid, { ...w297.inc.get(iid), timers: w297.inc.get(iid).timers.set("reaction", { ...w297.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w299 = { ...w298, inc: w298.inc.set(iid, { ...w298.inc.get(iid), timers: w298.inc.get(iid).timers.set("reaction", { ...w298.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w299
    } else {
      val w300 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_301 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w302 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_301) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w303 = { ...w302, inc: w302.inc.set(iid, { ...w302.inc.get(iid), timers: w302.inc.get(iid).timers.set("reaction", { ...w302.inc.get(iid).timers.get("reaction"), paused: keep_301 }) }) }
      val w304 = { ...w303, inc: w303.inc.set(iid, { ...w303.inc.get(iid), timers: w303.inc.get(iid).timers.set("reaction", { ...w303.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w305 = { ...w304, inc: w304.inc.set(iid, { ...w304.inc.get(iid), timers: w304.inc.get(iid).timers.set("reaction", { ...w304.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w305
    }
      w300
    }
      w295
    }
    w293
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w306 = if (timerDef("hold").startsOnce) {
      val w307 = ec_pauseTimer(w0, c, iid, "hold")
      w307
    } else {
      val w308 = if (false) {
      val w309 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w310 = { ...w309, inc: w309.inc.set(iid, { ...w309.inc.get(iid), timers: w309.inc.get(iid).timers.set("hold", { ...w309.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w311 = { ...w310, inc: w310.inc.set(iid, { ...w310.inc.get(iid), timers: w310.inc.get(iid).timers.set("hold", { ...w310.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w312 = { ...w311, inc: w311.inc.set(iid, { ...w311.inc.get(iid), timers: w311.inc.get(iid).timers.set("hold", { ...w311.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w312
    } else {
      val w313 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_314 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w315 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_314) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w316 = { ...w315, inc: w315.inc.set(iid, { ...w315.inc.get(iid), timers: w315.inc.get(iid).timers.set("hold", { ...w315.inc.get(iid).timers.get("hold"), paused: keep_314 }) }) }
      val w317 = { ...w316, inc: w316.inc.set(iid, { ...w316.inc.get(iid), timers: w316.inc.get(iid).timers.set("hold", { ...w316.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w318 = { ...w317, inc: w317.inc.set(iid, { ...w317.inc.get(iid), timers: w317.inc.get(iid).timers.set("hold", { ...w317.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w318
    }
      w313
    }
      w308
    }
    w306
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w319 = if (not(timerDef("resolution").pausable)) {
      val sec_320 = timerSec(w0.inc.get(iid), "resolution", "")
      val w321 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_320 < 0)) 0 else (c.now + (sec_320 * 1000))) }) }) }
      val w322 = { ...w321, inc: w321.inc.set(iid, { ...w321.inc.get(iid), timers: w321.inc.get(iid).timers.set("resolution", { ...w321.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w322
    } else {
      val w323 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_324 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w325 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_324 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_324)) }) }) }
      val w326 = { ...w325, inc: w325.inc.set(iid, { ...w325.inc.get(iid), timers: w325.inc.get(iid).timers.set("resolution", { ...w325.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w327 = { ...w326, inc: w326.inc.set(iid, { ...w326.inc.get(iid), timers: w326.inc.get(iid).timers.set("resolution", { ...w326.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w327
    } else w0
      w323
    }
    w319
  }

  def e_takeover_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_takeover_9(w0: World, c: Ctx, iid: str): World = {
    val whom_328 = c.before.owner
    val w329 = if (((whom_328 != "") and (whom_328 != c.actor))) w0 else w0
    w329
  }

  def apply_takeover(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_takeover_0(ws, c1, iid)
    val w2 = e_takeover_1(w1, c1, iid)
    val w3 = e_takeover_2(w2, c1, iid)
    val w4 = e_takeover_3(w3, c1, iid)
    val w5 = e_takeover_4(w4, c1, iid)
    val w6 = e_takeover_5(w5, c1, iid)
    val w7 = e_takeover_6(w6, c1, iid)
    val w8 = e_takeover_7(w7, c1, iid)
    val w9 = e_takeover_8(w8, c1, iid)
    val w10 = e_takeover_9(w9, c1, iid)
    w10
  }

  // close: manual → closed

  def ok_close(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    not(settings.session.states.foldl(false, (acc, s_330) => acc or ((s_330.id == agentState(c.me)) and s_330.readOnly))),
    { val os_331 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_331.foldl(false, (acc, o_332) => acc or ((o_332.id == c.form.resultId) and stepsOk(o_332, world.inc.get(iid)))) else os_331.foldl(false, (acc, o_333) => acc or stepsOk(o_333, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_334 = c.actor
    val w335 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_334 }) }
    w335
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_336 = ""
    val w337 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_336 }) }
    w337
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_338 = c.actor
    val w339 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_338 }) }
    w339
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_340 = c.now
    val w341 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_340 }) }
    w341
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_342 = c.form.resultId
    val w343 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_342 }) }
    w343
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_344 = c.form.causeId
    val w345 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_344 }) }
    w345
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_346 = c.form.comment
    val w347 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_346 }) }
    w347
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w348 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w348
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w349 = if (timerDef("reaction").startsOnce) {
      val w350 = ec_pauseTimer(w0, c, iid, "reaction")
      w350
    } else {
      val w351 = if (true) {
      val w352 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w353 = { ...w352, inc: w352.inc.set(iid, { ...w352.inc.get(iid), timers: w352.inc.get(iid).timers.set("reaction", { ...w352.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w354 = { ...w353, inc: w353.inc.set(iid, { ...w353.inc.get(iid), timers: w353.inc.get(iid).timers.set("reaction", { ...w353.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w355 = { ...w354, inc: w354.inc.set(iid, { ...w354.inc.get(iid), timers: w354.inc.get(iid).timers.set("reaction", { ...w354.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w355
    } else {
      val w356 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_357 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w358 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_357) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w359 = { ...w358, inc: w358.inc.set(iid, { ...w358.inc.get(iid), timers: w358.inc.get(iid).timers.set("reaction", { ...w358.inc.get(iid).timers.get("reaction"), paused: keep_357 }) }) }
      val w360 = { ...w359, inc: w359.inc.set(iid, { ...w359.inc.get(iid), timers: w359.inc.get(iid).timers.set("reaction", { ...w359.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w361 = { ...w360, inc: w360.inc.set(iid, { ...w360.inc.get(iid), timers: w360.inc.get(iid).timers.set("reaction", { ...w360.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w361
    }
      w356
    }
      w351
    }
    w349
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w362 = if (not(timerDef("resolution").pausable)) {
      val w363 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w364 = { ...w363, inc: w363.inc.set(iid, { ...w363.inc.get(iid), timers: w363.inc.get(iid).timers.set("resolution", { ...w363.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w364
    } else {
      val w365 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w366 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w367 = { ...w366, inc: w366.inc.set(iid, { ...w366.inc.get(iid), timers: w366.inc.get(iid).timers.set("resolution", { ...w366.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w368 = { ...w367, inc: w367.inc.set(iid, { ...w367.inc.get(iid), timers: w367.inc.get(iid).timers.set("resolution", { ...w367.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w368
    } else w0
      w365
    }
    w362
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w369 = if (timerDef("hold").startsOnce) {
      val w370 = ec_pauseTimer(w0, c, iid, "hold")
      w370
    } else {
      val w371 = if (false) {
      val w372 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w373 = { ...w372, inc: w372.inc.set(iid, { ...w372.inc.get(iid), timers: w372.inc.get(iid).timers.set("hold", { ...w372.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w374 = { ...w373, inc: w373.inc.set(iid, { ...w373.inc.get(iid), timers: w373.inc.get(iid).timers.set("hold", { ...w373.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w375 = { ...w374, inc: w374.inc.set(iid, { ...w374.inc.get(iid), timers: w374.inc.get(iid).timers.set("hold", { ...w374.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w375
    } else {
      val w376 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_377 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w378 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_377) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w379 = { ...w378, inc: w378.inc.set(iid, { ...w378.inc.get(iid), timers: w378.inc.get(iid).timers.set("hold", { ...w378.inc.get(iid).timers.get("hold"), paused: keep_377 }) }) }
      val w380 = { ...w379, inc: w379.inc.set(iid, { ...w379.inc.get(iid), timers: w379.inc.get(iid).timers.set("hold", { ...w379.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w381 = { ...w380, inc: w380.inc.set(iid, { ...w380.inc.get(iid), timers: w380.inc.get(iid).timers.set("hold", { ...w380.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w381
    }
      w376
    }
      w371
    }
    w369
  }

  def e_close_11(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_12(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_13(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_close(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "closed" }) }
    val w1 = e_close_0(ws, c1, iid)
    val w2 = e_close_1(w1, c1, iid)
    val w3 = e_close_2(w2, c1, iid)
    val w4 = e_close_3(w3, c1, iid)
    val w5 = e_close_4(w4, c1, iid)
    val w6 = e_close_5(w5, c1, iid)
    val w7 = e_close_6(w6, c1, iid)
    val w8 = e_close_7(w7, c1, iid)
    val w9 = e_close_8(w8, c1, iid)
    val w10 = e_close_9(w9, c1, iid)
    val w11 = e_close_10(w10, c1, iid)
    val w12 = e_close_11(w11, c1, iid)
    val w13 = e_close_12(w12, c1, iid)
    val w14 = e_close_13(w13, c1, iid)
    w14
  }

  // reopen: manual → in_progress

  def ok_reopen(c: Ctx, iid: str): bool = all {
    Set("closed").contains(world.inc.get(iid).state),
    can(c.me, "incident:reopen"),
    can(c.me, "incident:claim"),
    not(settings.session.states.foldl(false, (acc, s_382) => acc or ((s_382.id == agentState(c.me)) and s_382.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_383 = c.actor
    val w384 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_383 }) }
    w384
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w385 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_386 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w387 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w388 = { ...w387, inc: w387.inc.set(iid, { ...w387.inc.get(iid), linkedTo: "" }) }
      val w389 = { ...w388, inc: w388.inc.set(iid, { ...w388.inc.get(iid), linkedAt: 0 }) }
      val w390 = if (((ps_386.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w389 else w389
      val w391 = if (("workflow.journal.linked_reopened" != "")) {
      val w392 = ps_386.foldl([], (acc, x395) => acc.append(x395.id)).foldl(w390, (wf393, pId394) => wf393)
      w392
    } else w390
      w391
    } else {
      val w396 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w397 = { ...w396, inc: w396.inc.set(iid, { ...w396.inc.get(iid), linkedAt: 0 }) }
      w397
    }
    w385
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_398 = ""
    val w399 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_398 }) }
    w399
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_400 = ""
    val w401 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_400 }) }
    w401
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_402 = ""
    val w403 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_402 }) }
    w403
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_404 = 0
    val w405 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_404 }) }
    w405
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_406 = ""
    val w407 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_406 }) }
    w407
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val sec_408 = settings.limits.reopenResolutionSec
    val w409 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_408 > 0)) sec_408 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w410 = { ...w409, inc: w409.inc.set(iid, { ...w409.inc.get(iid), timers: w409.inc.get(iid).timers.set("resolution", { ...w409.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w411 = { ...w410, inc: w410.inc.set(iid, { ...w410.inc.get(iid), timers: w410.inc.get(iid).timers.set("resolution", { ...w410.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w411
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val w412 = if (timerDef("reaction").startsOnce) {
      val w413 = ec_pauseTimer(w0, c, iid, "reaction")
      w413
    } else {
      val w414 = if (true) {
      val w415 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w416 = { ...w415, inc: w415.inc.set(iid, { ...w415.inc.get(iid), timers: w415.inc.get(iid).timers.set("reaction", { ...w415.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w417 = { ...w416, inc: w416.inc.set(iid, { ...w416.inc.get(iid), timers: w416.inc.get(iid).timers.set("reaction", { ...w416.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w418 = { ...w417, inc: w417.inc.set(iid, { ...w417.inc.get(iid), timers: w417.inc.get(iid).timers.set("reaction", { ...w417.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w418
    } else {
      val w419 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_420 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w421 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_420) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w422 = { ...w421, inc: w421.inc.set(iid, { ...w421.inc.get(iid), timers: w421.inc.get(iid).timers.set("reaction", { ...w421.inc.get(iid).timers.get("reaction"), paused: keep_420 }) }) }
      val w423 = { ...w422, inc: w422.inc.set(iid, { ...w422.inc.get(iid), timers: w422.inc.get(iid).timers.set("reaction", { ...w422.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w424 = { ...w423, inc: w423.inc.set(iid, { ...w423.inc.get(iid), timers: w423.inc.get(iid).timers.set("reaction", { ...w423.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w424
    }
      w419
    }
      w414
    }
    w412
  }

  def e_reopen_10(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_reopen(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "in_progress" }) }
    val w1 = e_reopen_0(ws, c1, iid)
    val w2 = e_reopen_1(w1, c1, iid)
    val w3 = e_reopen_2(w2, c1, iid)
    val w4 = e_reopen_3(w3, c1, iid)
    val w5 = e_reopen_4(w4, c1, iid)
    val w6 = e_reopen_5(w5, c1, iid)
    val w7 = e_reopen_6(w6, c1, iid)
    val w8 = e_reopen_7(w7, c1, iid)
    val w9 = e_reopen_8(w8, c1, iid)
    val w10 = e_reopen_9(w9, c1, iid)
    val w11 = e_reopen_10(w10, c1, iid)
    w11
  }

  // auto_escalate: timer → pending_acceptance

  def ok_auto_escalate(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == true),
    { val t_425 = world.inc.get(iid).timers.get("reaction")  (((t_425.due != 0) and (t_425.due <= c.now)) and (t_425.fired != t_425.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_426 = personOf(levelUpTarget(c.before))
    val w427 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_426 }) }
    w427
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_428 = groupOf(levelUpTarget(c.before))
    val w429 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_428 }) }
    w429
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_430 = levelUpNumber(c.before)
    val w431 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_430 }) }
    w431
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w432 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w432
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w433 = if (not(timerDef("resolution").pausable)) {
      val w434 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w435 = { ...w434, inc: w434.inc.set(iid, { ...w434.inc.get(iid), timers: w434.inc.get(iid).timers.set("resolution", { ...w434.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w435
    } else {
      val w436 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w437 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w438 = { ...w437, inc: w437.inc.set(iid, { ...w437.inc.get(iid), timers: w437.inc.get(iid).timers.set("resolution", { ...w437.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w439 = { ...w438, inc: w438.inc.set(iid, { ...w438.inc.get(iid), timers: w438.inc.get(iid).timers.set("resolution", { ...w438.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w439
    } else w0
      w436
    }
    w433
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w440 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w441 = if (timerDef("reaction").startsOnce) {
      val w442 = ec_resumeTimer(w0, c, iid, "reaction")
      w442
    } else {
      val w443 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w444 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w445 = { ...w444, inc: w444.inc.set(iid, { ...w444.inc.get(iid), timers: w444.inc.get(iid).timers.set("reaction", { ...w444.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w446 = { ...w445, inc: w445.inc.set(iid, { ...w445.inc.get(iid), timers: w445.inc.get(iid).timers.set("reaction", { ...w445.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w446
    } else {
      val sec_447 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w448 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_447 < 0)) 0 else (c.now + (sec_447 * 1000))) }) }) }
      val w449 = { ...w448, inc: w448.inc.set(iid, { ...w448.inc.get(iid), timers: w448.inc.get(iid).timers.set("reaction", { ...w448.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w450 = { ...w449, inc: w449.inc.set(iid, { ...w449.inc.get(iid), timers: w449.inc.get(iid).timers.set("reaction", { ...w449.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w451 = { ...w450, inc: w450.inc.set(iid, { ...w450.inc.get(iid), timers: w450.inc.get(iid).timers.set("reaction", { ...w450.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w451
    }
      w443
    }
      w441
    }
    w440
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_452 = addressee(w0.inc.get(iid))
    val w453 = if (((whom_452 != "") and (whom_452 != c.actor))) w0 else w0
    w453
  }

  def apply_auto_escalate(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "pending_acceptance" }) }
    val w1 = e_auto_escalate_0(ws, c1, iid)
    val w2 = e_auto_escalate_1(w1, c1, iid)
    val w3 = e_auto_escalate_2(w2, c1, iid)
    val w4 = e_auto_escalate_3(w3, c1, iid)
    val w5 = e_auto_escalate_4(w4, c1, iid)
    val w6 = e_auto_escalate_5(w5, c1, iid)
    val w7 = e_auto_escalate_6(w6, c1, iid)
    val w8 = e_auto_escalate_7(w7, c1, iid)
    val w9 = e_auto_escalate_8(w8, c1, iid)
    w9
  }

  // escalation_ceiling: timer

  def ok_escalation_ceiling(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == true),
    { val t_454 = world.inc.get(iid).timers.get("reaction")  (((t_454.due != 0) and (t_454.due <= c.now)) and (t_454.fired != t_454.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_455 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w456 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_455) }) }
    val w457 = { ...w456, inc: w456.inc.set(iid, { ...w456.inc.get(iid), slaBreached: true }) }
    val w458 = groupMembersAt(incs(w0), w457.inc.get(iid), c.deadline).foldl([], (acc, x461) => acc.append(x461.id)).foldl(w457, (wf459, eId460) => {
      val w462 = { ...wf459, inc: wf459.inc.set(eId460, { ...wf459.inc.get(eId460), breaches: wf459.inc.get(eId460).breaches.append(breach_455) }) }
      val w463 = { ...w462, inc: w462.inc.set(eId460, { ...w462.inc.get(eId460), slaBreached: true }) }
      w463
    })
    w458
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w464 = if (timerDef("reaction").startsOnce) {
      val w465 = ec_pauseTimer(w0, c, iid, "reaction")
      w465
    } else {
      val w466 = if (false) {
      val w467 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w468 = { ...w467, inc: w467.inc.set(iid, { ...w467.inc.get(iid), timers: w467.inc.get(iid).timers.set("reaction", { ...w467.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w469 = { ...w468, inc: w468.inc.set(iid, { ...w468.inc.get(iid), timers: w468.inc.get(iid).timers.set("reaction", { ...w468.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w470 = { ...w469, inc: w469.inc.set(iid, { ...w469.inc.get(iid), timers: w469.inc.get(iid).timers.set("reaction", { ...w469.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w470
    } else {
      val w471 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_472 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w473 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_472) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w474 = { ...w473, inc: w473.inc.set(iid, { ...w473.inc.get(iid), timers: w473.inc.get(iid).timers.set("reaction", { ...w473.inc.get(iid).timers.get("reaction"), paused: keep_472 }) }) }
      val w475 = { ...w474, inc: w474.inc.set(iid, { ...w474.inc.get(iid), timers: w474.inc.get(iid).timers.set("reaction", { ...w474.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w476 = { ...w475, inc: w475.inc.set(iid, { ...w475.inc.get(iid), timers: w475.inc.get(iid).timers.set("reaction", { ...w475.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w476
    }
      w471
    }
      w466
    }
    w464
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_477 = settings.alerts.target
    val w478 = if (((whom_477 != "") and (whom_477 != c.actor))) w0 else w0
    w478
  }

  def apply_escalation_ceiling(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_escalation_ceiling_0(w0, c1, iid)
    val w2 = e_escalation_ceiling_1(w1, c1, iid)
    val w3 = e_escalation_ceiling_2(w2, c1, iid)
    val w4 = e_escalation_ceiling_3(w3, c1, iid)
    w4
  }

  // reaction_overdue: timer

  def ok_reaction_overdue(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == false),
    { val t_479 = world.inc.get(iid).timers.get("reaction")  (((t_479.due != 0) and (t_479.due <= c.now)) and (t_479.fired != t_479.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_480 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w481 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_480) }) }
    val w482 = { ...w481, inc: w481.inc.set(iid, { ...w481.inc.get(iid), slaBreached: true }) }
    val w483 = groupMembersAt(incs(w0), w482.inc.get(iid), c.deadline).foldl([], (acc, x486) => acc.append(x486.id)).foldl(w482, (wf484, eId485) => {
      val w487 = { ...wf484, inc: wf484.inc.set(eId485, { ...wf484.inc.get(eId485), breaches: wf484.inc.get(eId485).breaches.append(breach_480) }) }
      val w488 = { ...w487, inc: w487.inc.set(eId485, { ...w487.inc.get(eId485), slaBreached: true }) }
      w488
    })
    w483
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w489 = if (timerDef("reaction").startsOnce) {
      val w490 = ec_pauseTimer(w0, c, iid, "reaction")
      w490
    } else {
      val w491 = if (false) {
      val w492 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w493 = { ...w492, inc: w492.inc.set(iid, { ...w492.inc.get(iid), timers: w492.inc.get(iid).timers.set("reaction", { ...w492.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w494 = { ...w493, inc: w493.inc.set(iid, { ...w493.inc.get(iid), timers: w493.inc.get(iid).timers.set("reaction", { ...w493.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w495 = { ...w494, inc: w494.inc.set(iid, { ...w494.inc.get(iid), timers: w494.inc.get(iid).timers.set("reaction", { ...w494.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w495
    } else {
      val w496 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_497 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w498 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_497) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w499 = { ...w498, inc: w498.inc.set(iid, { ...w498.inc.get(iid), timers: w498.inc.get(iid).timers.set("reaction", { ...w498.inc.get(iid).timers.get("reaction"), paused: keep_497 }) }) }
      val w500 = { ...w499, inc: w499.inc.set(iid, { ...w499.inc.get(iid), timers: w499.inc.get(iid).timers.set("reaction", { ...w499.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w501 = { ...w500, inc: w500.inc.set(iid, { ...w500.inc.get(iid), timers: w500.inc.get(iid).timers.set("reaction", { ...w500.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w501
    }
      w496
    }
      w491
    }
    w489
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_502 = settings.alerts.target
    val w503 = if (((whom_502 != "") and (whom_502 != c.actor))) w0 else w0
    w503
  }

  def apply_reaction_overdue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_reaction_overdue_0(w0, c1, iid)
    val w2 = e_reaction_overdue_1(w1, c1, iid)
    val w3 = e_reaction_overdue_2(w2, c1, iid)
    val w4 = e_reaction_overdue_3(w3, c1, iid)
    w4
  }

  // resolution_overdue: timer

  def ok_resolution_overdue(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    { val t_504 = world.inc.get(iid).timers.get("resolution")  (((t_504.due != 0) and (t_504.due <= c.now)) and (t_504.fired != t_504.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_505 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w506 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_505) }) }
    val w507 = { ...w506, inc: w506.inc.set(iid, { ...w506.inc.get(iid), slaBreached: true }) }
    val w508 = groupMembersAt(incs(w0), w507.inc.get(iid), c.deadline).foldl([], (acc, x511) => acc.append(x511.id)).foldl(w507, (wf509, eId510) => {
      val w512 = { ...wf509, inc: wf509.inc.set(eId510, { ...wf509.inc.get(eId510), breaches: wf509.inc.get(eId510).breaches.append(breach_505) }) }
      val w513 = { ...w512, inc: w512.inc.set(eId510, { ...w512.inc.get(eId510), slaBreached: true }) }
      w513
    })
    w508
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_514 = settings.alerts.target
    val w515 = if (((whom_514 != "") and (whom_514 != c.actor))) w0 else w0
    w515
  }

  def apply_resolution_overdue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_resolution_overdue_0(w0, c1, iid)
    val w2 = e_resolution_overdue_1(w1, c1, iid)
    val w3 = e_resolution_overdue_2(w2, c1, iid)
    w3
  }

  // resolution_escalate: timer → pending_acceptance

  def ok_resolution_escalate(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (settings.escalation.onResolutionOverdue == "escalate"),
    { val t_516 = world.inc.get(iid).timers.get("resolution")  (((t_516.due != 0) and (t_516.due <= c.now)) and (t_516.fired != t_516.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_517 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w518 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_517) }) }
    val w519 = { ...w518, inc: w518.inc.set(iid, { ...w518.inc.get(iid), slaBreached: true }) }
    val w520 = groupMembersAt(incs(w0), w519.inc.get(iid), c.deadline).foldl([], (acc, x523) => acc.append(x523.id)).foldl(w519, (wf521, eId522) => {
      val w524 = { ...wf521, inc: wf521.inc.set(eId522, { ...wf521.inc.get(eId522), breaches: wf521.inc.get(eId522).breaches.append(breach_517) }) }
      val w525 = { ...w524, inc: w524.inc.set(eId522, { ...w524.inc.get(eId522), slaBreached: true }) }
      w525
    })
    w520
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_526 = personOf(levelUpTarget(c.before))
    val w527 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_526 }) }
    w527
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_528 = groupOf(levelUpTarget(c.before))
    val w529 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_528 }) }
    w529
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_530 = levelUpNumber(c.before)
    val w531 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_530 }) }
    w531
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w532 = if (not(timerDef("resolution").pausable)) {
      val w533 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w534 = { ...w533, inc: w533.inc.set(iid, { ...w533.inc.get(iid), timers: w533.inc.get(iid).timers.set("resolution", { ...w533.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w534
    } else {
      val w535 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w536 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w537 = { ...w536, inc: w536.inc.set(iid, { ...w536.inc.get(iid), timers: w536.inc.get(iid).timers.set("resolution", { ...w536.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w538 = { ...w537, inc: w537.inc.set(iid, { ...w537.inc.get(iid), timers: w537.inc.get(iid).timers.set("resolution", { ...w537.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w538
    } else w0
      w535
    }
    w532
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w539 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w540 = if (timerDef("reaction").startsOnce) {
      val w541 = ec_resumeTimer(w0, c, iid, "reaction")
      w541
    } else {
      val w542 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w543 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w544 = { ...w543, inc: w543.inc.set(iid, { ...w543.inc.get(iid), timers: w543.inc.get(iid).timers.set("reaction", { ...w543.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w545 = { ...w544, inc: w544.inc.set(iid, { ...w544.inc.get(iid), timers: w544.inc.get(iid).timers.set("reaction", { ...w544.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w545
    } else {
      val sec_546 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w547 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_546 < 0)) 0 else (c.now + (sec_546 * 1000))) }) }) }
      val w548 = { ...w547, inc: w547.inc.set(iid, { ...w547.inc.get(iid), timers: w547.inc.get(iid).timers.set("reaction", { ...w547.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w549 = { ...w548, inc: w548.inc.set(iid, { ...w548.inc.get(iid), timers: w548.inc.get(iid).timers.set("reaction", { ...w548.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w550 = { ...w549, inc: w549.inc.set(iid, { ...w549.inc.get(iid), timers: w549.inc.get(iid).timers.set("reaction", { ...w549.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w550
    }
      w542
    }
      w540
    }
    w539
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_551 = c.before.owner
    val w552 = if (((whom_551 != "") and (whom_551 != c.actor))) w0 else w0
    w552
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_553 = addressee(w0.inc.get(iid))
    val w554 = if (((whom_553 != "") and (whom_553 != c.actor))) w0 else w0
    w554
  }

  def apply_resolution_escalate(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "pending_acceptance" }) }
    val w1 = e_resolution_escalate_0(ws, c1, iid)
    val w2 = e_resolution_escalate_1(w1, c1, iid)
    val w3 = e_resolution_escalate_2(w2, c1, iid)
    val w4 = e_resolution_escalate_3(w3, c1, iid)
    val w5 = e_resolution_escalate_4(w4, c1, iid)
    val w6 = e_resolution_escalate_5(w5, c1, iid)
    val w7 = e_resolution_escalate_6(w6, c1, iid)
    val w8 = e_resolution_escalate_7(w7, c1, iid)
    val w9 = e_resolution_escalate_8(w8, c1, iid)
    val w10 = e_resolution_escalate_9(w9, c1, iid)
    w10
  }

  // resolution_ceiling: timer

  def ok_resolution_ceiling(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (settings.escalation.onResolutionOverdue == "escalate"),
    { val t_555 = world.inc.get(iid).timers.get("resolution")  (((t_555.due != 0) and (t_555.due <= c.now)) and (t_555.fired != t_555.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_556 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w557 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_556) }) }
    val w558 = { ...w557, inc: w557.inc.set(iid, { ...w557.inc.get(iid), slaBreached: true }) }
    val w559 = groupMembersAt(incs(w0), w558.inc.get(iid), c.deadline).foldl([], (acc, x562) => acc.append(x562.id)).foldl(w558, (wf560, eId561) => {
      val w563 = { ...wf560, inc: wf560.inc.set(eId561, { ...wf560.inc.get(eId561), breaches: wf560.inc.get(eId561).breaches.append(breach_556) }) }
      val w564 = { ...w563, inc: w563.inc.set(eId561, { ...w563.inc.get(eId561), slaBreached: true }) }
      w564
    })
    w559
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_565 = settings.alerts.target
    val w566 = if (((whom_565 != "") and (whom_565 != c.actor))) w0 else w0
    w566
  }

  def apply_resolution_ceiling(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_resolution_ceiling_0(w0, c1, iid)
    val w2 = e_resolution_ceiling_1(w1, c1, iid)
    val w3 = e_resolution_ceiling_2(w2, c1, iid)
    w3
  }

  // hold_overdue: timer

  def ok_hold_overdue(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    { val t_567 = world.inc.get(iid).timers.get("hold")  (((t_567.due != 0) and (t_567.due <= c.now)) and (t_567.fired != t_567.due)) },
    not(["break", "no_link"].foldl(false, (acc, y568) => acc or y568 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_569 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w570 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_569) }) }
    val w571 = { ...w570, inc: w570.inc.set(iid, { ...w570.inc.get(iid), slaBreached: true }) }
    val w572 = groupMembersAt(incs(w0), w571.inc.get(iid), c.deadline).foldl([], (acc, x575) => acc.append(x575.id)).foldl(w571, (wf573, eId574) => {
      val w576 = { ...wf573, inc: wf573.inc.set(eId574, { ...wf573.inc.get(eId574), breaches: wf573.inc.get(eId574).breaches.append(breach_569) }) }
      val w577 = { ...w576, inc: w576.inc.set(eId574, { ...w576.inc.get(eId574), slaBreached: true }) }
      w577
    })
    w572
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_578 = settings.alerts.target
    val w579 = if (((whom_578 != "") and (whom_578 != c.actor))) w0 else w0
    w579
  }

  def apply_hold_overdue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_hold_overdue_0(w0, c1, iid)
    val w2 = e_hold_overdue_1(w1, c1, iid)
    val w3 = e_hold_overdue_2(w2, c1, iid)
    w3
  }

  // break_hold_release: timer → new

  def ok_break_hold_release(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    { val t_580 = world.inc.get(iid).timers.get("hold")  (((t_580.due != 0) and (t_580.due <= c.now)) and (t_580.fired != t_580.due)) },
    ["break"].foldl(false, (acc, y581) => acc or y581 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_582 = ""
    val w583 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_582 }) }
    w583
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w584 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w584
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w585 = if (timerDef("hold").startsOnce) {
      val w586 = ec_pauseTimer(w0, c, iid, "hold")
      w586
    } else {
      val w587 = if (false) {
      val w588 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w589 = { ...w588, inc: w588.inc.set(iid, { ...w588.inc.get(iid), timers: w588.inc.get(iid).timers.set("hold", { ...w588.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w590 = { ...w589, inc: w589.inc.set(iid, { ...w589.inc.get(iid), timers: w589.inc.get(iid).timers.set("hold", { ...w589.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w591 = { ...w590, inc: w590.inc.set(iid, { ...w590.inc.get(iid), timers: w590.inc.get(iid).timers.set("hold", { ...w590.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w591
    } else {
      val w592 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_593 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w594 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_593) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w595 = { ...w594, inc: w594.inc.set(iid, { ...w594.inc.get(iid), timers: w594.inc.get(iid).timers.set("hold", { ...w594.inc.get(iid).timers.get("hold"), paused: keep_593 }) }) }
      val w596 = { ...w595, inc: w595.inc.set(iid, { ...w595.inc.get(iid), timers: w595.inc.get(iid).timers.set("hold", { ...w595.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w597 = { ...w596, inc: w596.inc.set(iid, { ...w596.inc.get(iid), timers: w596.inc.get(iid).timers.set("hold", { ...w596.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w597
    }
      w592
    }
      w587
    }
    w585
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w598 = if (not(timerDef("resolution").pausable)) {
      val w599 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w600 = { ...w599, inc: w599.inc.set(iid, { ...w599.inc.get(iid), timers: w599.inc.get(iid).timers.set("resolution", { ...w599.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w600
    } else {
      val w601 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w602 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w603 = { ...w602, inc: w602.inc.set(iid, { ...w602.inc.get(iid), timers: w602.inc.get(iid).timers.set("resolution", { ...w602.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w604 = { ...w603, inc: w603.inc.set(iid, { ...w603.inc.get(iid), timers: w603.inc.get(iid).timers.set("resolution", { ...w603.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w604
    } else w0
      w601
    }
    w598
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w605 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w606 = if (timerDef("reaction").startsOnce) {
      val w607 = ec_resumeTimer(w0, c, iid, "reaction")
      w607
    } else {
      val w608 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w609 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w610 = { ...w609, inc: w609.inc.set(iid, { ...w609.inc.get(iid), timers: w609.inc.get(iid).timers.set("reaction", { ...w609.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w611 = { ...w610, inc: w610.inc.set(iid, { ...w610.inc.get(iid), timers: w610.inc.get(iid).timers.set("reaction", { ...w610.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w611
    } else {
      val sec_612 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w613 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_612 < 0)) 0 else (c.now + (sec_612 * 1000))) }) }) }
      val w614 = { ...w613, inc: w613.inc.set(iid, { ...w613.inc.get(iid), timers: w613.inc.get(iid).timers.set("reaction", { ...w613.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w615 = { ...w614, inc: w614.inc.set(iid, { ...w614.inc.get(iid), timers: w614.inc.get(iid).timers.set("reaction", { ...w614.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w616 = { ...w615, inc: w615.inc.set(iid, { ...w615.inc.get(iid), timers: w615.inc.get(iid).timers.set("reaction", { ...w615.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w616
    }
      w608
    }
      w606
    }
    w605
  }

  def e_break_hold_release_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_break_hold_release_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_break_hold_release(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_break_hold_release_0(ws, c1, iid)
    val w2 = e_break_hold_release_1(w1, c1, iid)
    val w3 = e_break_hold_release_2(w2, c1, iid)
    val w4 = e_break_hold_release_3(w3, c1, iid)
    val w5 = e_break_hold_release_4(w4, c1, iid)
    val w6 = e_break_hold_release_5(w5, c1, iid)
    val w7 = e_break_hold_release_6(w6, c1, iid)
    w7
  }

  // system_hold_break: system → on_hold

  def ok_system_hold_break(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (agentState(c.me) == "not_ready"),
  }

  def e_system_hold_break_0(w0: World, c: Ctx, iid: str): World = {
    val reason_617 = "break"
    val w618 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_617 }) }
    w618
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w619 = if (not(timerDef("resolution").pausable)) {
      val w620 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w621 = { ...w620, inc: w620.inc.set(iid, { ...w620.inc.get(iid), timers: w620.inc.get(iid).timers.set("resolution", { ...w620.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w621
    } else {
      val w622 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w623 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w624 = { ...w623, inc: w623.inc.set(iid, { ...w623.inc.get(iid), timers: w623.inc.get(iid).timers.set("resolution", { ...w623.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w625 = { ...w624, inc: w624.inc.set(iid, { ...w624.inc.get(iid), timers: w624.inc.get(iid).timers.set("resolution", { ...w624.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w625
    } else w0
      w622
    }
    w619
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w626 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w627 = if (timerDef("hold").startsOnce) {
      val w628 = ec_resumeTimer(w0, c, iid, "hold")
      w628
    } else {
      val w629 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w630 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w631 = { ...w630, inc: w630.inc.set(iid, { ...w630.inc.get(iid), timers: w630.inc.get(iid).timers.set("hold", { ...w630.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w632 = { ...w631, inc: w631.inc.set(iid, { ...w631.inc.get(iid), timers: w631.inc.get(iid).timers.set("hold", { ...w631.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w632
    } else {
      val sec_633 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w634 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_633 < 0)) 0 else (c.now + (sec_633 * 1000))) }) }) }
      val w635 = { ...w634, inc: w634.inc.set(iid, { ...w634.inc.get(iid), timers: w634.inc.get(iid).timers.set("hold", { ...w634.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w636 = { ...w635, inc: w635.inc.set(iid, { ...w635.inc.get(iid), timers: w635.inc.get(iid).timers.set("hold", { ...w635.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w637 = { ...w636, inc: w636.inc.set(iid, { ...w636.inc.get(iid), timers: w636.inc.get(iid).timers.set("hold", { ...w636.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w637
    }
      w629
    }
      w627
    }
    w626
  }

  def e_system_hold_break_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_system_hold_break(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "on_hold" }) }
    val w1 = e_system_hold_break_0(ws, c1, iid)
    val w2 = e_system_hold_break_1(w1, c1, iid)
    val w3 = e_system_hold_break_2(w2, c1, iid)
    val w4 = e_system_hold_break_3(w3, c1, iid)
    w4
  }

  // system_hold_idle: system → on_hold

  def ok_system_hold_idle(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (idleSec(c.me) >= settings.session.idleHoldSec),
  }

  def e_system_hold_idle_0(w0: World, c: Ctx, iid: str): World = {
    val reason_638 = "no_link"
    val w639 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_638 }) }
    w639
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w640 = if (not(timerDef("resolution").pausable)) {
      val w641 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w642 = { ...w641, inc: w641.inc.set(iid, { ...w641.inc.get(iid), timers: w641.inc.get(iid).timers.set("resolution", { ...w641.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w642
    } else {
      val w643 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w644 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w645 = { ...w644, inc: w644.inc.set(iid, { ...w644.inc.get(iid), timers: w644.inc.get(iid).timers.set("resolution", { ...w644.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w646 = { ...w645, inc: w645.inc.set(iid, { ...w645.inc.get(iid), timers: w645.inc.get(iid).timers.set("resolution", { ...w645.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w646
    } else w0
      w643
    }
    w640
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w647 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w648 = if (timerDef("hold").startsOnce) {
      val w649 = ec_resumeTimer(w0, c, iid, "hold")
      w649
    } else {
      val w650 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w651 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w652 = { ...w651, inc: w651.inc.set(iid, { ...w651.inc.get(iid), timers: w651.inc.get(iid).timers.set("hold", { ...w651.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w653 = { ...w652, inc: w652.inc.set(iid, { ...w652.inc.get(iid), timers: w652.inc.get(iid).timers.set("hold", { ...w652.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w653
    } else {
      val sec_654 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w655 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_654 < 0)) 0 else (c.now + (sec_654 * 1000))) }) }) }
      val w656 = { ...w655, inc: w655.inc.set(iid, { ...w655.inc.get(iid), timers: w655.inc.get(iid).timers.set("hold", { ...w655.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w657 = { ...w656, inc: w656.inc.set(iid, { ...w656.inc.get(iid), timers: w656.inc.get(iid).timers.set("hold", { ...w656.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w658 = { ...w657, inc: w657.inc.set(iid, { ...w657.inc.get(iid), timers: w657.inc.get(iid).timers.set("hold", { ...w657.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w658
    }
      w650
    }
      w648
    }
    w647
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_659 = settings.alerts.target
    val w660 = if (((whom_659 != "") and (whom_659 != c.actor))) w0 else w0
    w660
  }

  def apply_system_hold_idle(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "on_hold" }) }
    val w1 = e_system_hold_idle_0(ws, c1, iid)
    val w2 = e_system_hold_idle_1(w1, c1, iid)
    val w3 = e_system_hold_idle_2(w2, c1, iid)
    val w4 = e_system_hold_idle_3(w3, c1, iid)
    val w5 = e_system_hold_idle_4(w4, c1, iid)
    w5
  }

  // system_release_idle: system → new

  def ok_system_release_idle(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    (idleSec(c.me) >= settings.session.idleReleaseSec),
    ["break", "no_link"].foldl(false, (acc, y661) => acc or y661 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_662 = ""
    val w663 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_662 }) }
    w663
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w664 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w664
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w665 = if (timerDef("hold").startsOnce) {
      val w666 = ec_pauseTimer(w0, c, iid, "hold")
      w666
    } else {
      val w667 = if (false) {
      val w668 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w669 = { ...w668, inc: w668.inc.set(iid, { ...w668.inc.get(iid), timers: w668.inc.get(iid).timers.set("hold", { ...w668.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w670 = { ...w669, inc: w669.inc.set(iid, { ...w669.inc.get(iid), timers: w669.inc.get(iid).timers.set("hold", { ...w669.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w671 = { ...w670, inc: w670.inc.set(iid, { ...w670.inc.get(iid), timers: w670.inc.get(iid).timers.set("hold", { ...w670.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w671
    } else {
      val w672 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_673 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w674 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_673) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w675 = { ...w674, inc: w674.inc.set(iid, { ...w674.inc.get(iid), timers: w674.inc.get(iid).timers.set("hold", { ...w674.inc.get(iid).timers.get("hold"), paused: keep_673 }) }) }
      val w676 = { ...w675, inc: w675.inc.set(iid, { ...w675.inc.get(iid), timers: w675.inc.get(iid).timers.set("hold", { ...w675.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w677 = { ...w676, inc: w676.inc.set(iid, { ...w676.inc.get(iid), timers: w676.inc.get(iid).timers.set("hold", { ...w676.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w677
    }
      w672
    }
      w667
    }
    w665
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w678 = if (not(timerDef("resolution").pausable)) {
      val w679 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w680 = { ...w679, inc: w679.inc.set(iid, { ...w679.inc.get(iid), timers: w679.inc.get(iid).timers.set("resolution", { ...w679.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w680
    } else {
      val w681 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w682 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w683 = { ...w682, inc: w682.inc.set(iid, { ...w682.inc.get(iid), timers: w682.inc.get(iid).timers.set("resolution", { ...w682.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w684 = { ...w683, inc: w683.inc.set(iid, { ...w683.inc.get(iid), timers: w683.inc.get(iid).timers.set("resolution", { ...w683.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w684
    } else w0
      w681
    }
    w678
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w685 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w686 = if (timerDef("reaction").startsOnce) {
      val w687 = ec_resumeTimer(w0, c, iid, "reaction")
      w687
    } else {
      val w688 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w689 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w690 = { ...w689, inc: w689.inc.set(iid, { ...w689.inc.get(iid), timers: w689.inc.get(iid).timers.set("reaction", { ...w689.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w691 = { ...w690, inc: w690.inc.set(iid, { ...w690.inc.get(iid), timers: w690.inc.get(iid).timers.set("reaction", { ...w690.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w691
    } else {
      val sec_692 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w693 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_692 < 0)) 0 else (c.now + (sec_692 * 1000))) }) }) }
      val w694 = { ...w693, inc: w693.inc.set(iid, { ...w693.inc.get(iid), timers: w693.inc.get(iid).timers.set("reaction", { ...w693.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w695 = { ...w694, inc: w694.inc.set(iid, { ...w694.inc.get(iid), timers: w694.inc.get(iid).timers.set("reaction", { ...w694.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w696 = { ...w695, inc: w695.inc.set(iid, { ...w695.inc.get(iid), timers: w695.inc.get(iid).timers.set("reaction", { ...w695.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w696
    }
      w688
    }
      w686
    }
    w685
  }

  def e_system_release_idle_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_system_release_idle(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_system_release_idle_0(ws, c1, iid)
    val w2 = e_system_release_idle_1(w1, c1, iid)
    val w3 = e_system_release_idle_2(w2, c1, iid)
    val w4 = e_system_release_idle_3(w3, c1, iid)
    val w5 = e_system_release_idle_4(w4, c1, iid)
    val w6 = e_system_release_idle_5(w5, c1, iid)
    w6
  }

  // no_link_hold_release: timer → new

  def ok_no_link_hold_release(c: Ctx, iid: str): bool = all {
    Set("on_hold").contains(world.inc.get(iid).state),
    { val t_697 = world.inc.get(iid).timers.get("hold")  (((t_697.due != 0) and (t_697.due <= c.now)) and (t_697.fired != t_697.due)) },
    ["no_link"].foldl(false, (acc, y698) => acc or y698 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_699 = ""
    val w700 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_699 }) }
    w700
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w701 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w701
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w702 = if (timerDef("hold").startsOnce) {
      val w703 = ec_pauseTimer(w0, c, iid, "hold")
      w703
    } else {
      val w704 = if (false) {
      val w705 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w706 = { ...w705, inc: w705.inc.set(iid, { ...w705.inc.get(iid), timers: w705.inc.get(iid).timers.set("hold", { ...w705.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w707 = { ...w706, inc: w706.inc.set(iid, { ...w706.inc.get(iid), timers: w706.inc.get(iid).timers.set("hold", { ...w706.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w708 = { ...w707, inc: w707.inc.set(iid, { ...w707.inc.get(iid), timers: w707.inc.get(iid).timers.set("hold", { ...w707.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w708
    } else {
      val w709 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_710 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w711 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_710) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w712 = { ...w711, inc: w711.inc.set(iid, { ...w711.inc.get(iid), timers: w711.inc.get(iid).timers.set("hold", { ...w711.inc.get(iid).timers.get("hold"), paused: keep_710 }) }) }
      val w713 = { ...w712, inc: w712.inc.set(iid, { ...w712.inc.get(iid), timers: w712.inc.get(iid).timers.set("hold", { ...w712.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w714 = { ...w713, inc: w713.inc.set(iid, { ...w713.inc.get(iid), timers: w713.inc.get(iid).timers.set("hold", { ...w713.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w714
    }
      w709
    }
      w704
    }
    w702
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w715 = if (not(timerDef("resolution").pausable)) {
      val w716 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w717 = { ...w716, inc: w716.inc.set(iid, { ...w716.inc.get(iid), timers: w716.inc.get(iid).timers.set("resolution", { ...w716.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w717
    } else {
      val w718 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w719 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w720 = { ...w719, inc: w719.inc.set(iid, { ...w719.inc.get(iid), timers: w719.inc.get(iid).timers.set("resolution", { ...w719.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w721 = { ...w720, inc: w720.inc.set(iid, { ...w720.inc.get(iid), timers: w720.inc.get(iid).timers.set("resolution", { ...w720.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w721
    } else w0
      w718
    }
    w715
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w722 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w723 = if (timerDef("reaction").startsOnce) {
      val w724 = ec_resumeTimer(w0, c, iid, "reaction")
      w724
    } else {
      val w725 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w726 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w727 = { ...w726, inc: w726.inc.set(iid, { ...w726.inc.get(iid), timers: w726.inc.get(iid).timers.set("reaction", { ...w726.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w728 = { ...w727, inc: w727.inc.set(iid, { ...w727.inc.get(iid), timers: w727.inc.get(iid).timers.set("reaction", { ...w727.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w728
    } else {
      val sec_729 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w730 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_729 < 0)) 0 else (c.now + (sec_729 * 1000))) }) }) }
      val w731 = { ...w730, inc: w730.inc.set(iid, { ...w730.inc.get(iid), timers: w730.inc.get(iid).timers.set("reaction", { ...w730.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w732 = { ...w731, inc: w731.inc.set(iid, { ...w731.inc.get(iid), timers: w731.inc.get(iid).timers.set("reaction", { ...w731.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w733 = { ...w732, inc: w732.inc.set(iid, { ...w732.inc.get(iid), timers: w732.inc.get(iid).timers.set("reaction", { ...w732.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w733
    }
      w725
    }
      w723
    }
    w722
  }

  def e_no_link_hold_release_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_no_link_hold_release_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_no_link_hold_release(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_no_link_hold_release_0(ws, c1, iid)
    val w2 = e_no_link_hold_release_1(w1, c1, iid)
    val w3 = e_no_link_hold_release_2(w2, c1, iid)
    val w4 = e_no_link_hold_release_3(w3, c1, iid)
    val w5 = e_no_link_hold_release_4(w4, c1, iid)
    val w6 = e_no_link_hold_release_5(w5, c1, iid)
    val w7 = e_no_link_hold_release_6(w6, c1, iid)
    w7
  }

  // addressee_signed_out_to_group: system → pending_acceptance

  def ok_addressee_signed_out_to_group(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    (agentState(c.me) == "offline"),
    (((world.inc.get(iid).owner != "") and (dutyGroupOf(world.inc.get(iid).owner) != "")) == true),
  }

  def e_addressee_signed_out_to_group_0(w0: World, c: Ctx, iid: str): World = {
    val group_734 = dutyGroupOf(w0.inc.get(iid).owner)
    val w735 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_734 }) }
    w735
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_736 = ""
    val w737 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_736 }) }
    w737
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_738 = addressee(w0.inc.get(iid))
    val w739 = if (((whom_738 != "") and (whom_738 != c.actor))) w0 else w0
    w739
  }

  def apply_addressee_signed_out_to_group(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "pending_acceptance" }) }
    val w1 = e_addressee_signed_out_to_group_0(ws, c1, iid)
    val w2 = e_addressee_signed_out_to_group_1(w1, c1, iid)
    val w3 = e_addressee_signed_out_to_group_2(w2, c1, iid)
    val w4 = e_addressee_signed_out_to_group_3(w3, c1, iid)
    w4
  }

  // addressee_signed_out_to_queue: system → new

  def ok_addressee_signed_out_to_queue(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    (agentState(c.me) == "offline"),
    (((world.inc.get(iid).owner != "") and (dutyGroupOf(world.inc.get(iid).owner) != "")) == false),
  }

  def e_addressee_signed_out_to_queue_0(w0: World, c: Ctx, iid: str): World = {
    val who_740 = ""
    val w741 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_740 }) }
    w741
  }

  def e_addressee_signed_out_to_queue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_addressee_signed_out_to_queue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_addressee_signed_out_to_queue_0(ws, c1, iid)
    val w2 = e_addressee_signed_out_to_queue_1(w1, c1, iid)
    w2
  }

  // owner_signed_out: system → new

  def ok_owner_signed_out(c: Ctx, iid: str): bool = all {
    Set("in_progress", "on_hold").contains(world.inc.get(iid).state),
    (agentState(c.me) == "offline"),
  }

  def e_owner_signed_out_0(w0: World, c: Ctx, iid: str): World = {
    val who_742 = ""
    val w743 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_742 }) }
    w743
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w744 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w744
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w745 = if (timerDef("hold").startsOnce) {
      val w746 = ec_pauseTimer(w0, c, iid, "hold")
      w746
    } else {
      val w747 = if (false) {
      val w748 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w749 = { ...w748, inc: w748.inc.set(iid, { ...w748.inc.get(iid), timers: w748.inc.get(iid).timers.set("hold", { ...w748.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w750 = { ...w749, inc: w749.inc.set(iid, { ...w749.inc.get(iid), timers: w749.inc.get(iid).timers.set("hold", { ...w749.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w751 = { ...w750, inc: w750.inc.set(iid, { ...w750.inc.get(iid), timers: w750.inc.get(iid).timers.set("hold", { ...w750.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w751
    } else {
      val w752 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_753 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w754 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_753) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w755 = { ...w754, inc: w754.inc.set(iid, { ...w754.inc.get(iid), timers: w754.inc.get(iid).timers.set("hold", { ...w754.inc.get(iid).timers.get("hold"), paused: keep_753 }) }) }
      val w756 = { ...w755, inc: w755.inc.set(iid, { ...w755.inc.get(iid), timers: w755.inc.get(iid).timers.set("hold", { ...w755.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w757 = { ...w756, inc: w756.inc.set(iid, { ...w756.inc.get(iid), timers: w756.inc.get(iid).timers.set("hold", { ...w756.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w757
    }
      w752
    }
      w747
    }
    w745
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w758 = if (not(timerDef("resolution").pausable)) {
      val w759 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w760 = { ...w759, inc: w759.inc.set(iid, { ...w759.inc.get(iid), timers: w759.inc.get(iid).timers.set("resolution", { ...w759.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w760
    } else {
      val w761 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w762 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w763 = { ...w762, inc: w762.inc.set(iid, { ...w762.inc.get(iid), timers: w762.inc.get(iid).timers.set("resolution", { ...w762.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w764 = { ...w763, inc: w763.inc.set(iid, { ...w763.inc.get(iid), timers: w763.inc.get(iid).timers.set("resolution", { ...w763.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w764
    } else w0
      w761
    }
    w758
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w765 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w766 = if (timerDef("reaction").startsOnce) {
      val w767 = ec_resumeTimer(w0, c, iid, "reaction")
      w767
    } else {
      val w768 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w769 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w770 = { ...w769, inc: w769.inc.set(iid, { ...w769.inc.get(iid), timers: w769.inc.get(iid).timers.set("reaction", { ...w769.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w771 = { ...w770, inc: w770.inc.set(iid, { ...w770.inc.get(iid), timers: w770.inc.get(iid).timers.set("reaction", { ...w770.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w771
    } else {
      val sec_772 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w773 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_772 < 0)) 0 else (c.now + (sec_772 * 1000))) }) }) }
      val w774 = { ...w773, inc: w773.inc.set(iid, { ...w773.inc.get(iid), timers: w773.inc.get(iid).timers.set("reaction", { ...w773.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w775 = { ...w774, inc: w774.inc.set(iid, { ...w774.inc.get(iid), timers: w774.inc.get(iid).timers.set("reaction", { ...w774.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w776 = { ...w775, inc: w775.inc.set(iid, { ...w775.inc.get(iid), timers: w775.inc.get(iid).timers.set("reaction", { ...w775.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w776
    }
      w768
    }
      w766
    }
    w765
  }

  def e_owner_signed_out_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_owner_signed_out(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_owner_signed_out_0(ws, c1, iid)
    val w2 = e_owner_signed_out_1(w1, c1, iid)
    val w3 = e_owner_signed_out_2(w2, c1, iid)
    val w4 = e_owner_signed_out_3(w3, c1, iid)
    val w5 = e_owner_signed_out_4(w4, c1, iid)
    val w6 = e_owner_signed_out_5(w5, c1, iid)
    w6
  }

  // addressee_lost_access: system → new

  def ok_addressee_lost_access(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    ((addressee(world.inc.get(iid)) != "") and (hasAccess(addressee(world.inc.get(iid)), world.inc.get(iid)) == false)),
  }

  def e_addressee_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val who_777 = ""
    val w778 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_777 }) }
    w778
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_779 = ""
    val w780 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_779 }) }
    w780
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w781 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w781
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w782 = if (timerDef("hold").startsOnce) {
      val w783 = ec_pauseTimer(w0, c, iid, "hold")
      w783
    } else {
      val w784 = if (false) {
      val w785 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w786 = { ...w785, inc: w785.inc.set(iid, { ...w785.inc.get(iid), timers: w785.inc.get(iid).timers.set("hold", { ...w785.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w787 = { ...w786, inc: w786.inc.set(iid, { ...w786.inc.get(iid), timers: w786.inc.get(iid).timers.set("hold", { ...w786.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w788 = { ...w787, inc: w787.inc.set(iid, { ...w787.inc.get(iid), timers: w787.inc.get(iid).timers.set("hold", { ...w787.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w788
    } else {
      val w789 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_790 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w791 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_790) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w792 = { ...w791, inc: w791.inc.set(iid, { ...w791.inc.get(iid), timers: w791.inc.get(iid).timers.set("hold", { ...w791.inc.get(iid).timers.get("hold"), paused: keep_790 }) }) }
      val w793 = { ...w792, inc: w792.inc.set(iid, { ...w792.inc.get(iid), timers: w792.inc.get(iid).timers.set("hold", { ...w792.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w794 = { ...w793, inc: w793.inc.set(iid, { ...w793.inc.get(iid), timers: w793.inc.get(iid).timers.set("hold", { ...w793.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w794
    }
      w789
    }
      w784
    }
    w782
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w795 = if (not(timerDef("resolution").pausable)) {
      val w796 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w797 = { ...w796, inc: w796.inc.set(iid, { ...w796.inc.get(iid), timers: w796.inc.get(iid).timers.set("resolution", { ...w796.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w797
    } else {
      val w798 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w799 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w800 = { ...w799, inc: w799.inc.set(iid, { ...w799.inc.get(iid), timers: w799.inc.get(iid).timers.set("resolution", { ...w799.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w801 = { ...w800, inc: w800.inc.set(iid, { ...w800.inc.get(iid), timers: w800.inc.get(iid).timers.set("resolution", { ...w800.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w801
    } else w0
      w798
    }
    w795
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w802 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w803 = if (timerDef("reaction").startsOnce) {
      val w804 = ec_resumeTimer(w0, c, iid, "reaction")
      w804
    } else {
      val w805 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w806 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w807 = { ...w806, inc: w806.inc.set(iid, { ...w806.inc.get(iid), timers: w806.inc.get(iid).timers.set("reaction", { ...w806.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w808 = { ...w807, inc: w807.inc.set(iid, { ...w807.inc.get(iid), timers: w807.inc.get(iid).timers.set("reaction", { ...w807.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w808
    } else {
      val sec_809 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w810 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_809 < 0)) 0 else (c.now + (sec_809 * 1000))) }) }) }
      val w811 = { ...w810, inc: w810.inc.set(iid, { ...w810.inc.get(iid), timers: w810.inc.get(iid).timers.set("reaction", { ...w810.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w812 = { ...w811, inc: w811.inc.set(iid, { ...w811.inc.get(iid), timers: w811.inc.get(iid).timers.set("reaction", { ...w811.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w813 = { ...w812, inc: w812.inc.set(iid, { ...w812.inc.get(iid), timers: w812.inc.get(iid).timers.set("reaction", { ...w812.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w813
    }
      w805
    }
      w803
    }
    w802
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_814 = settings.alerts.target
    val w815 = if (((whom_814 != "") and (whom_814 != c.actor))) w0 else w0
    w815
  }

  def apply_addressee_lost_access(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_addressee_lost_access_0(ws, c1, iid)
    val w2 = e_addressee_lost_access_1(w1, c1, iid)
    val w3 = e_addressee_lost_access_2(w2, c1, iid)
    val w4 = e_addressee_lost_access_3(w3, c1, iid)
    val w5 = e_addressee_lost_access_4(w4, c1, iid)
    val w6 = e_addressee_lost_access_5(w5, c1, iid)
    val w7 = e_addressee_lost_access_6(w6, c1, iid)
    val w8 = e_addressee_lost_access_7(w7, c1, iid)
    val w9 = e_addressee_lost_access_8(w8, c1, iid)
    w9
  }

  // addressee_cannot_accept: system → new

  def ok_addressee_cannot_accept(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    ((addressee(world.inc.get(iid)) != "") and (hasAccess(addressee(world.inc.get(iid)), world.inc.get(iid)) == true)),
    ((addressee(world.inc.get(iid)) != "") and (canAccept(addressee(world.inc.get(iid)), world.inc.get(iid), "") == false)),
  }

  def e_addressee_cannot_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_816 = ""
    val w817 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_816 }) }
    w817
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_818 = ""
    val w819 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_818 }) }
    w819
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w820 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w821 = if (timerDef("reaction").startsOnce) {
      val w822 = ec_resumeTimer(w0, c, iid, "reaction")
      w822
    } else {
      val w823 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w824 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w825 = { ...w824, inc: w824.inc.set(iid, { ...w824.inc.get(iid), timers: w824.inc.get(iid).timers.set("reaction", { ...w824.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w826 = { ...w825, inc: w825.inc.set(iid, { ...w825.inc.get(iid), timers: w825.inc.get(iid).timers.set("reaction", { ...w825.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w826
    } else {
      val sec_827 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w828 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_827 < 0)) 0 else (c.now + (sec_827 * 1000))) }) }) }
      val w829 = { ...w828, inc: w828.inc.set(iid, { ...w828.inc.get(iid), timers: w828.inc.get(iid).timers.set("reaction", { ...w828.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w830 = { ...w829, inc: w829.inc.set(iid, { ...w829.inc.get(iid), timers: w829.inc.get(iid).timers.set("reaction", { ...w829.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w831 = { ...w830, inc: w830.inc.set(iid, { ...w830.inc.get(iid), timers: w830.inc.get(iid).timers.set("reaction", { ...w830.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w831
    }
      w823
    }
      w821
    }
    w820
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_832 = settings.alerts.target
    val w833 = if (((whom_832 != "") and (whom_832 != c.actor))) w0 else w0
    w833
  }

  def apply_addressee_cannot_accept(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_addressee_cannot_accept_0(ws, c1, iid)
    val w2 = e_addressee_cannot_accept_1(w1, c1, iid)
    val w3 = e_addressee_cannot_accept_2(w2, c1, iid)
    val w4 = e_addressee_cannot_accept_3(w3, c1, iid)
    val w5 = e_addressee_cannot_accept_4(w4, c1, iid)
    val w6 = e_addressee_cannot_accept_5(w5, c1, iid)
    w6
  }

  // merge: manual → linked

  def ok_merge(c: Ctx, iid: str): bool = all {
    Set("new", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    can(c.me, "incident:bulk"),
    not(settings.session.states.foldl(false, (acc, s_834) => acc or ((s_834.id == agentState(c.me)) and s_834.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_835 = incidentById(incs(world), c.form.primaryId)  ((((ps_835.length() > 0) and (ps_835[0].id != world.inc.get(iid).id)) and (ps_835[0].linkedTo == "")) and ((ps_835[0].state == "new") or ((ps_835[0].state == "in_progress") and (ps_835[0].owner == c.me)))) },
    { val ps_836 = incidentById(incs(world), c.form.primaryId)  ((ps_836.length() > 0) and (ps_836[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w837 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w837
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_838 = incidentById(incs(w0), c.form.primaryId)
    val w839 = if ((ps_838.length() > 0)) {
      val w840 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_847 => not(isDone(e_847))).foldl([], (acc, x843) => acc.append(x843.id)).foldl(w0, (wf841, cId842) => {
      val w844 = { ...wf841, inc: wf841.inc.set(cId842, { ...wf841.inc.get(cId842), leftGroup: { primaryId: wf841.inc.get(cId842).linkedTo, linkedAt: wf841.inc.get(cId842).linkedAt, at: c.now } }) }
      val w845 = { ...w844, inc: w844.inc.set(cId842, { ...w844.inc.get(cId842), linkedTo: ps_838[0].id }) }
      val w846 = { ...w845, inc: w845.inc.set(cId842, { ...w845.inc.get(cId842), linkedAt: c.now }) }
      w846
    })
      w840
    } else w0
    w839
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_848 = c.form.primaryId
    val w849 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_848 }) }
    val w850 = { ...w849, inc: w849.inc.set(iid, { ...w849.inc.get(iid), linkedAt: c.now }) }
    w850
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_851 = ""
    val w852 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_851 }) }
    w852
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_853 = ""
    val w854 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_853 }) }
    w854
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w855 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w855
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w856 = if (timerDef("reaction").startsOnce) {
      val w857 = ec_pauseTimer(w0, c, iid, "reaction")
      w857
    } else {
      val w858 = if (false) {
      val w859 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w860 = { ...w859, inc: w859.inc.set(iid, { ...w859.inc.get(iid), timers: w859.inc.get(iid).timers.set("reaction", { ...w859.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w861 = { ...w860, inc: w860.inc.set(iid, { ...w860.inc.get(iid), timers: w860.inc.get(iid).timers.set("reaction", { ...w860.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w862 = { ...w861, inc: w861.inc.set(iid, { ...w861.inc.get(iid), timers: w861.inc.get(iid).timers.set("reaction", { ...w861.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w862
    } else {
      val w863 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_864 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w865 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_864) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w866 = { ...w865, inc: w865.inc.set(iid, { ...w865.inc.get(iid), timers: w865.inc.get(iid).timers.set("reaction", { ...w865.inc.get(iid).timers.get("reaction"), paused: keep_864 }) }) }
      val w867 = { ...w866, inc: w866.inc.set(iid, { ...w866.inc.get(iid), timers: w866.inc.get(iid).timers.set("reaction", { ...w866.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w868 = { ...w867, inc: w867.inc.set(iid, { ...w867.inc.get(iid), timers: w867.inc.get(iid).timers.set("reaction", { ...w867.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w868
    }
      w863
    }
      w858
    }
    w856
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w869 = if (not(timerDef("resolution").pausable)) {
      val w870 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w871 = { ...w870, inc: w870.inc.set(iid, { ...w870.inc.get(iid), timers: w870.inc.get(iid).timers.set("resolution", { ...w870.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w871
    } else {
      val w872 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w873 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w874 = { ...w873, inc: w873.inc.set(iid, { ...w873.inc.get(iid), timers: w873.inc.get(iid).timers.set("resolution", { ...w873.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w875 = { ...w874, inc: w874.inc.set(iid, { ...w874.inc.get(iid), timers: w874.inc.get(iid).timers.set("resolution", { ...w874.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w875
    } else w0
      w872
    }
    w869
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_876 = incidentById(incs(w0), c.form.primaryId)
    val w877 = if (((((ps_876.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_876[0], "resolution", c.now)))) {
      val t_878 = ps_876[0].timers.get("resolution")
      val left_879 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_880 = (if ((t_878.due != 0)) (t_878.due - c.now) else (if (t_878.paused) t_878.left else (timerSec(ps_876[0], "resolution", "") * 1000)))
      val w881 = if ((left_879 < was_880)) {
      val w882 = ps_876.foldl([], (acc, x885) => acc.append(x885.id)).foldl(w0, (wf883, pId884) => {
      val w886 = if ((t_878.due != 0)) {
      val w887 = { ...wf883, inc: wf883.inc.set(pId884, { ...wf883.inc.get(pId884), timers: wf883.inc.get(pId884).timers.set("resolution", { ...wf883.inc.get(pId884).timers.get("resolution"), due: (c.now + left_879) }) }) }
      w887
    } else {
      val w888 = { ...wf883, inc: wf883.inc.set(pId884, { ...wf883.inc.get(pId884), timers: wf883.inc.get(pId884).timers.set("resolution", { ...wf883.inc.get(pId884).timers.get("resolution"), left: left_879 }) }) }
      val w889 = { ...w888, inc: w888.inc.set(pId884, { ...w888.inc.get(pId884), timers: w888.inc.get(pId884).timers.set("resolution", { ...w888.inc.get(pId884).timers.get("resolution"), paused: true }) }) }
      w889
    }
      w886
    })
      w882
    } else w0
      w881
    } else w0
    w877
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w890 = if (timerDef("hold").startsOnce) {
      val w891 = ec_pauseTimer(w0, c, iid, "hold")
      w891
    } else {
      val w892 = if (false) {
      val w893 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w894 = { ...w893, inc: w893.inc.set(iid, { ...w893.inc.get(iid), timers: w893.inc.get(iid).timers.set("hold", { ...w893.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w895 = { ...w894, inc: w894.inc.set(iid, { ...w894.inc.get(iid), timers: w894.inc.get(iid).timers.set("hold", { ...w894.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w896 = { ...w895, inc: w895.inc.set(iid, { ...w895.inc.get(iid), timers: w895.inc.get(iid).timers.set("hold", { ...w895.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w896
    } else {
      val w897 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_898 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w899 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_898) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w900 = { ...w899, inc: w899.inc.set(iid, { ...w899.inc.get(iid), timers: w899.inc.get(iid).timers.set("hold", { ...w899.inc.get(iid).timers.get("hold"), paused: keep_898 }) }) }
      val w901 = { ...w900, inc: w900.inc.set(iid, { ...w900.inc.get(iid), timers: w900.inc.get(iid).timers.set("hold", { ...w900.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w902 = { ...w901, inc: w901.inc.set(iid, { ...w901.inc.get(iid), timers: w901.inc.get(iid).timers.set("hold", { ...w901.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w902
    }
      w897
    }
      w892
    }
    w890
  }

  def e_merge_10(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_merge(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "linked" }) }
    val w1 = e_merge_0(ws, c1, iid)
    val w2 = e_merge_1(w1, c1, iid)
    val w3 = e_merge_2(w2, c1, iid)
    val w4 = e_merge_3(w3, c1, iid)
    val w5 = e_merge_4(w4, c1, iid)
    val w6 = e_merge_5(w5, c1, iid)
    val w7 = e_merge_6(w6, c1, iid)
    val w8 = e_merge_7(w7, c1, iid)
    val w9 = e_merge_8(w8, c1, iid)
    val w10 = e_merge_9(w9, c1, iid)
    val w11 = e_merge_10(w10, c1, iid)
    w11
  }

  // detach: manual → new

  def ok_detach(c: Ctx, iid: str): bool = all {
    Set("linked").contains(world.inc.get(iid).state),
    not(settings.session.states.foldl(false, (acc, s_903) => acc or ((s_903.id == agentState(c.me)) and s_903.readOnly))),
    { val ps_904 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_904.length() > 0) and ((ownership(c.me, ps_904[0]) == "owner") or unowned(ps_904[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_905 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w906 = if (((ps_905.length() > 0) and (leftOf(ps_905[0], "resolution", c.now) >= 0))) {
      val w907 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w908 = { ...w907, inc: w907.inc.set(iid, { ...w907.inc.get(iid), timers: w907.inc.get(iid).timers.set("resolution", { ...w907.inc.get(iid).timers.get("resolution"), left: leftOf(ps_905[0], "resolution", c.now) }) }) }
      val w909 = { ...w908, inc: w908.inc.set(iid, { ...w908.inc.get(iid), timers: w908.inc.get(iid).timers.set("resolution", { ...w908.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w910 = if ((leftOf(ps_905[0], "resolution", c.now) == 0)) {
      val w911 = { ...w909, inc: w909.inc.set(iid, { ...w909.inc.get(iid), timers: w909.inc.get(iid).timers.set("resolution", { ...w909.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_905[0], "resolution", c.now)) ps_905[0].timers.get("resolution").fired else ps_905[0].timers.get("resolution").due) }) }) }
      w911
    } else w909
      w910
    } else w0
    w906
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w912 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_913 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w914 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w915 = { ...w914, inc: w914.inc.set(iid, { ...w914.inc.get(iid), linkedTo: "" }) }
      val w916 = { ...w915, inc: w915.inc.set(iid, { ...w915.inc.get(iid), linkedAt: 0 }) }
      val w917 = if (((ps_913.length() > 0) and ("" != ""))) w916 else w916
      val w918 = if (("" != "")) {
      val w919 = ps_913.foldl([], (acc, x922) => acc.append(x922.id)).foldl(w917, (wf920, pId921) => wf920)
      w919
    } else w917
      w918
    } else {
      val w923 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w924 = { ...w923, inc: w923.inc.set(iid, { ...w923.inc.get(iid), linkedAt: 0 }) }
      w924
    }
    w912
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w925 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w926 = if (timerDef("reaction").startsOnce) {
      val w927 = ec_resumeTimer(w0, c, iid, "reaction")
      w927
    } else {
      val w928 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w929 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w930 = { ...w929, inc: w929.inc.set(iid, { ...w929.inc.get(iid), timers: w929.inc.get(iid).timers.set("reaction", { ...w929.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w931 = { ...w930, inc: w930.inc.set(iid, { ...w930.inc.get(iid), timers: w930.inc.get(iid).timers.set("reaction", { ...w930.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w931
    } else {
      val sec_932 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w933 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_932 < 0)) 0 else (c.now + (sec_932 * 1000))) }) }) }
      val w934 = { ...w933, inc: w933.inc.set(iid, { ...w933.inc.get(iid), timers: w933.inc.get(iid).timers.set("reaction", { ...w933.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w935 = { ...w934, inc: w934.inc.set(iid, { ...w934.inc.get(iid), timers: w934.inc.get(iid).timers.set("reaction", { ...w934.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w936 = { ...w935, inc: w935.inc.set(iid, { ...w935.inc.get(iid), timers: w935.inc.get(iid).timers.set("reaction", { ...w935.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w936
    }
      w928
    }
      w926
    }
    w925
  }

  def e_detach_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_detach(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_detach_0(ws, c1, iid)
    val w2 = e_detach_1(w1, c1, iid)
    val w3 = e_detach_2(w2, c1, iid)
    val w4 = e_detach_3(w3, c1, iid)
    val w5 = e_detach_4(w4, c1, iid)
    w5
  }

  // close_linked: system → closed

  def ok_close_linked(c: Ctx, iid: str): bool = all {
    Set("linked").contains(world.inc.get(iid).state),
    { val ps_937 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_937.length() > 0) and isDone(ps_937[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_938 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w939 = if ((ps_938.length() > 0)) {
      val w940 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_938[0].closeResultId }) }
      val w941 = { ...w940, inc: w940.inc.set(iid, { ...w940.inc.get(iid), closeCauseId: ps_938[0].closeCauseId }) }
      val w942 = { ...w941, inc: w941.inc.set(iid, { ...w941.inc.get(iid), result: ps_938[0].result }) }
      val w943 = { ...w942, inc: w942.inc.set(iid, { ...w942.inc.get(iid), closedBy: ps_938[0].closedBy }) }
      val w944 = { ...w943, inc: w943.inc.set(iid, { ...w943.inc.get(iid), owner: ps_938[0].closedBy }) }
      w944
    } else w0
    w939
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w945 = if (not(timerDef("resolution").pausable)) {
      val w946 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w947 = { ...w946, inc: w946.inc.set(iid, { ...w946.inc.get(iid), timers: w946.inc.get(iid).timers.set("resolution", { ...w946.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w947
    } else {
      val w948 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w949 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w950 = { ...w949, inc: w949.inc.set(iid, { ...w949.inc.get(iid), timers: w949.inc.get(iid).timers.set("resolution", { ...w949.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w951 = { ...w950, inc: w950.inc.set(iid, { ...w950.inc.get(iid), timers: w950.inc.get(iid).timers.set("resolution", { ...w950.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w951
    } else w0
      w948
    }
    w945
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_952 = c.now
    val w953 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_952 }) }
    w953
  }

  def e_close_linked_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_close_linked_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_close_linked(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "closed" }) }
    val w1 = e_close_linked_0(ws, c1, iid)
    val w2 = e_close_linked_1(w1, c1, iid)
    val w3 = e_close_linked_2(w2, c1, iid)
    val w4 = e_close_linked_3(w3, c1, iid)
    val w5 = e_close_linked_4(w4, c1, iid)
    w5
  }

  // linked_lost_access: system → new

  def ok_linked_lost_access(c: Ctx, iid: str): bool = all {
    Set("linked").contains(world.inc.get(iid).state),
    { val ps_954 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_955 = (if (((ps_954.length() > 0) and not(isDone(ps_954[0])))) addressee(ps_954[0]) else "")  ((who_955 != "") and (hasAccess(who_955, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_956 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w957 = if (((ps_956.length() > 0) and (leftOf(ps_956[0], "resolution", c.now) >= 0))) {
      val w958 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w959 = { ...w958, inc: w958.inc.set(iid, { ...w958.inc.get(iid), timers: w958.inc.get(iid).timers.set("resolution", { ...w958.inc.get(iid).timers.get("resolution"), left: leftOf(ps_956[0], "resolution", c.now) }) }) }
      val w960 = { ...w959, inc: w959.inc.set(iid, { ...w959.inc.get(iid), timers: w959.inc.get(iid).timers.set("resolution", { ...w959.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w961 = if ((leftOf(ps_956[0], "resolution", c.now) == 0)) {
      val w962 = { ...w960, inc: w960.inc.set(iid, { ...w960.inc.get(iid), timers: w960.inc.get(iid).timers.set("resolution", { ...w960.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_956[0], "resolution", c.now)) ps_956[0].timers.get("resolution").fired else ps_956[0].timers.get("resolution").due) }) }) }
      w962
    } else w960
      w961
    } else w0
    w957
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w963 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_964 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w965 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w966 = { ...w965, inc: w965.inc.set(iid, { ...w965.inc.get(iid), linkedTo: "" }) }
      val w967 = { ...w966, inc: w966.inc.set(iid, { ...w966.inc.get(iid), linkedAt: 0 }) }
      val w968 = if (((ps_964.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w967 else w967
      val w969 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w970 = ps_964.foldl([], (acc, x973) => acc.append(x973.id)).foldl(w968, (wf971, pId972) => wf971)
      w970
    } else w968
      w969
    } else {
      val w974 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w975 = { ...w974, inc: w974.inc.set(iid, { ...w974.inc.get(iid), linkedAt: 0 }) }
      w975
    }
    w963
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w976 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w977 = if (timerDef("reaction").startsOnce) {
      val w978 = ec_resumeTimer(w0, c, iid, "reaction")
      w978
    } else {
      val w979 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w980 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w981 = { ...w980, inc: w980.inc.set(iid, { ...w980.inc.get(iid), timers: w980.inc.get(iid).timers.set("reaction", { ...w980.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w982 = { ...w981, inc: w981.inc.set(iid, { ...w981.inc.get(iid), timers: w981.inc.get(iid).timers.set("reaction", { ...w981.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w982
    } else {
      val sec_983 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w984 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_983 < 0)) 0 else (c.now + (sec_983 * 1000))) }) }) }
      val w985 = { ...w984, inc: w984.inc.set(iid, { ...w984.inc.get(iid), timers: w984.inc.get(iid).timers.set("reaction", { ...w984.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w986 = { ...w985, inc: w985.inc.set(iid, { ...w985.inc.get(iid), timers: w985.inc.get(iid).timers.set("reaction", { ...w985.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w987 = { ...w986, inc: w986.inc.set(iid, { ...w986.inc.get(iid), timers: w986.inc.get(iid).timers.set("reaction", { ...w986.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w987
    }
      w979
    }
      w977
    }
    w976
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_988 = settings.alerts.target
    val w989 = if (((whom_988 != "") and (whom_988 != c.actor))) w0 else w0
    w989
  }

  def apply_linked_lost_access(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "new" }) }
    val w1 = e_linked_lost_access_0(ws, c1, iid)
    val w2 = e_linked_lost_access_1(w1, c1, iid)
    val w3 = e_linked_lost_access_2(w2, c1, iid)
    val w4 = e_linked_lost_access_3(w3, c1, iid)
    val w5 = e_linked_lost_access_4(w4, c1, iid)
    w5
  }

  def form_hold(c: Ctx, iid: str): bool = all {
    c.form.reasonId == "" or all {
      Set("third_party", "patrol", "no_data", "break", "no_link").contains(c.form.reasonId),
      settings.holdReasons.foldl(false, (acc, r_990) => acc or ((r_990.id == c.form.reasonId) and (r_990.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_991) => acc and (isDone(e_991) or hasAccess(c.form.targetId, e_991))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_992) => acc or (i_992.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_993) => acc or ((i_993.id == c.form.resultId) and stepsOk(i_993, world.inc.get(iid)))),
    },
    c.form.causeId == "" or all {
      (c.form.resultId == "mass"),
      Set("power", "link", "mass_fault", "known").contains(c.form.causeId),
    },
  }

  def formOk(tid: str, c: Ctx, iid: str): bool =
    if (tid == "hold") form_hold(c, iid)
    else if (tid == "transfer") form_transfer(c, iid)
    else if (tid == "close") form_close(c, iid)
    else true

  def trOk(tid: str, c: Ctx, iid: str): bool =
    if (tid == "create") ok_create(c, iid)
    else if (tid == "claim") ok_claim(c, iid)
    else if (tid == "accept") ok_accept(c, iid)
    else if (tid == "reject") ok_reject(c, iid)
    else if (tid == "hold") ok_hold(c, iid)
    else if (tid == "resume") ok_resume(c, iid)
    else if (tid == "release") ok_release(c, iid)
    else if (tid == "transfer") ok_transfer(c, iid)
    else if (tid == "takeover") ok_takeover(c, iid)
    else if (tid == "close") ok_close(c, iid)
    else if (tid == "reopen") ok_reopen(c, iid)
    else if (tid == "auto_escalate") ok_auto_escalate(c, iid)
    else if (tid == "escalation_ceiling") ok_escalation_ceiling(c, iid)
    else if (tid == "reaction_overdue") ok_reaction_overdue(c, iid)
    else if (tid == "resolution_overdue") ok_resolution_overdue(c, iid)
    else if (tid == "resolution_escalate") ok_resolution_escalate(c, iid)
    else if (tid == "resolution_ceiling") ok_resolution_ceiling(c, iid)
    else if (tid == "hold_overdue") ok_hold_overdue(c, iid)
    else if (tid == "break_hold_release") ok_break_hold_release(c, iid)
    else if (tid == "system_hold_break") ok_system_hold_break(c, iid)
    else if (tid == "system_hold_idle") ok_system_hold_idle(c, iid)
    else if (tid == "system_release_idle") ok_system_release_idle(c, iid)
    else if (tid == "no_link_hold_release") ok_no_link_hold_release(c, iid)
    else if (tid == "addressee_signed_out_to_group") ok_addressee_signed_out_to_group(c, iid)
    else if (tid == "addressee_signed_out_to_queue") ok_addressee_signed_out_to_queue(c, iid)
    else if (tid == "owner_signed_out") ok_owner_signed_out(c, iid)
    else if (tid == "addressee_lost_access") ok_addressee_lost_access(c, iid)
    else if (tid == "addressee_cannot_accept") ok_addressee_cannot_accept(c, iid)
    else if (tid == "merge") ok_merge(c, iid)
    else if (tid == "detach") ok_detach(c, iid)
    else if (tid == "close_linked") ok_close_linked(c, iid)
    else if (tid == "linked_lost_access") ok_linked_lost_access(c, iid)
    else false

  def trApply(tid: str, c: Ctx, iid: str, w: World): World =
    if (tid == "create") apply_create(c, iid, w)
    else if (tid == "claim") apply_claim(c, iid, w)
    else if (tid == "accept") apply_accept(c, iid, w)
    else if (tid == "reject") apply_reject(c, iid, w)
    else if (tid == "hold") apply_hold(c, iid, w)
    else if (tid == "resume") apply_resume(c, iid, w)
    else if (tid == "release") apply_release(c, iid, w)
    else if (tid == "transfer") apply_transfer(c, iid, w)
    else if (tid == "takeover") apply_takeover(c, iid, w)
    else if (tid == "close") apply_close(c, iid, w)
    else if (tid == "reopen") apply_reopen(c, iid, w)
    else if (tid == "auto_escalate") apply_auto_escalate(c, iid, w)
    else if (tid == "escalation_ceiling") apply_escalation_ceiling(c, iid, w)
    else if (tid == "reaction_overdue") apply_reaction_overdue(c, iid, w)
    else if (tid == "resolution_overdue") apply_resolution_overdue(c, iid, w)
    else if (tid == "resolution_escalate") apply_resolution_escalate(c, iid, w)
    else if (tid == "resolution_ceiling") apply_resolution_ceiling(c, iid, w)
    else if (tid == "hold_overdue") apply_hold_overdue(c, iid, w)
    else if (tid == "break_hold_release") apply_break_hold_release(c, iid, w)
    else if (tid == "system_hold_break") apply_system_hold_break(c, iid, w)
    else if (tid == "system_hold_idle") apply_system_hold_idle(c, iid, w)
    else if (tid == "system_release_idle") apply_system_release_idle(c, iid, w)
    else if (tid == "no_link_hold_release") apply_no_link_hold_release(c, iid, w)
    else if (tid == "addressee_signed_out_to_group") apply_addressee_signed_out_to_group(c, iid, w)
    else if (tid == "addressee_signed_out_to_queue") apply_addressee_signed_out_to_queue(c, iid, w)
    else if (tid == "owner_signed_out") apply_owner_signed_out(c, iid, w)
    else if (tid == "addressee_lost_access") apply_addressee_lost_access(c, iid, w)
    else if (tid == "addressee_cannot_accept") apply_addressee_cannot_accept(c, iid, w)
    else if (tid == "merge") apply_merge(c, iid, w)
    else if (tid == "detach") apply_detach(c, iid, w)
    else if (tid == "close_linked") apply_close_linked(c, iid, w)
    else if (tid == "linked_lost_access") apply_linked_lost_access(c, iid, w)
    else w

  pure val TRANSITIONS: List[Transition] = [
    { id: "create", trigger: "event", actor: "dispatcher", from: Set(), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "claim", trigger: "manual", actor: "dispatcher", from: Set("new"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "accept", trigger: "manual", actor: "dispatcher", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "reject", trigger: "manual", actor: "dispatcher", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "hold", trigger: "manual", actor: "dispatcher", from: Set("in_progress"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
    { id: "resume", trigger: "manual", actor: "dispatcher", from: Set("on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "release", trigger: "manual", actor: "dispatcher", from: Set("in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
    { id: "transfer", trigger: "manual", actor: "dispatcher", from: Set("new", "pending_acceptance", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "takeover", trigger: "manual", actor: "dispatcher", from: Set("pending_acceptance", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
    { id: "close", trigger: "manual", actor: "dispatcher", from: Set("new", "pending_acceptance", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "reopen", trigger: "manual", actor: "dispatcher", from: Set("closed"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("queue", "card"), bulkOnly: false },
    { id: "auto_escalate", trigger: "timer", actor: "dispatcher", from: Set("new", "pending_acceptance"), timer: "reaction", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "escalation_ceiling", trigger: "timer", actor: "dispatcher", from: Set("new", "pending_acceptance"), timer: "reaction", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "reaction_overdue", trigger: "timer", actor: "dispatcher", from: Set("new", "pending_acceptance"), timer: "reaction", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "resolution_overdue", trigger: "timer", actor: "dispatcher", from: Set("in_progress"), timer: "resolution", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "resolution_escalate", trigger: "timer", actor: "dispatcher", from: Set("in_progress"), timer: "resolution", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "resolution_ceiling", trigger: "timer", actor: "dispatcher", from: Set("in_progress"), timer: "resolution", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "hold_overdue", trigger: "timer", actor: "dispatcher", from: Set("on_hold"), timer: "hold", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "break_hold_release", trigger: "timer", actor: "system", from: Set("on_hold"), timer: "hold", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "system_hold_break", trigger: "system", actor: "system", from: Set("in_progress"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "system_hold_idle", trigger: "system", actor: "system", from: Set("in_progress"), timer: "", idleSec: MACHINE_SETTINGS.session.idleHoldSec, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "system_release_idle", trigger: "system", actor: "system", from: Set("on_hold"), timer: "", idleSec: MACHINE_SETTINGS.session.idleReleaseSec, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "no_link_hold_release", trigger: "timer", actor: "system", from: Set("on_hold"), timer: "hold", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "addressee_signed_out_to_group", trigger: "system", actor: "system", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "addressee_signed_out_to_queue", trigger: "system", actor: "system", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "owner_signed_out", trigger: "system", actor: "system", from: Set("in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "addressee_lost_access", trigger: "system", actor: "system", from: Set("pending_acceptance", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "addressee_cannot_accept", trigger: "system", actor: "system", from: Set("pending_acceptance"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "merge", trigger: "manual", actor: "dispatcher", from: Set("new", "in_progress", "on_hold"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: true },
    { id: "detach", trigger: "manual", actor: "dispatcher", from: Set("linked"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set("card"), bulkOnly: false },
    { id: "close_linked", trigger: "system", actor: "system", from: Set("linked"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
    { id: "linked_lost_access", trigger: "system", actor: "system", from: Set("linked"), timer: "", idleSec: 0, ownedByAgent: false, surfaces: Set(), bulkOnly: false },
  ]

  def windowBreach(tid: str, c: Ctx, iid: str, w: World): World =
    if (tid == "escalation_ceiling") e_escalation_ceiling_0(w, c, iid)
    else if (tid == "reaction_overdue") e_reaction_overdue_0(w, c, iid)
    else if (tid == "resolution_overdue") e_resolution_overdue_0(w, c, iid)
    else if (tid == "resolution_escalate") e_resolution_escalate_0(w, c, iid)
    else if (tid == "resolution_ceiling") e_resolution_ceiling_0(w, c, iid)
    else if (tid == "hold_overdue") e_hold_overdue_0(w, c, iid)
    else w

  pure val CONTINUES_ON: str -> Set[str] = Map("reaction" -> Set("addressee_signed_out_to_group", "addressee_signed_out_to_queue", "transfer", "reject"), "resolution" -> Set(), "hold" -> Set())

  pure val GRACE_MS: int = 3000

  pure val TAKE_WITH: str = "claim"

  pure val MERGE: str = "merge"

  val reached_create = lastAction.name == "create"
  val reached_claim = lastAction.name == "claim"
  val reached_accept = lastAction.name == "accept"
  val reached_reject = lastAction.name == "reject"
  val reached_hold = lastAction.name == "hold"
  val reached_resume = lastAction.name == "resume"
  val reached_release = lastAction.name == "release"
  val reached_transfer = lastAction.name == "transfer"
  val reached_takeover = lastAction.name == "takeover"
  val reached_close = lastAction.name == "close"
  val reached_reopen = lastAction.name == "reopen"
  val reached_auto_escalate = lastAction.name == "auto_escalate"
  val reached_escalation_ceiling = lastAction.name == "escalation_ceiling"
  val reached_reaction_overdue = lastAction.name == "reaction_overdue"
  val reached_resolution_overdue = lastAction.name == "resolution_overdue"
  val reached_resolution_escalate = lastAction.name == "resolution_escalate"
  val reached_resolution_ceiling = lastAction.name == "resolution_ceiling"
  val reached_hold_overdue = lastAction.name == "hold_overdue"
  val reached_break_hold_release = lastAction.name == "break_hold_release"
  val reached_system_hold_break = lastAction.name == "system_hold_break"
  val reached_system_hold_idle = lastAction.name == "system_hold_idle"
  val reached_system_release_idle = lastAction.name == "system_release_idle"
  val reached_no_link_hold_release = lastAction.name == "no_link_hold_release"
  val reached_addressee_signed_out_to_group = lastAction.name == "addressee_signed_out_to_group"
  val reached_addressee_signed_out_to_queue = lastAction.name == "addressee_signed_out_to_queue"
  val reached_owner_signed_out = lastAction.name == "owner_signed_out"
  val reached_addressee_lost_access = lastAction.name == "addressee_lost_access"
  val reached_addressee_cannot_accept = lastAction.name == "addressee_cannot_accept"
  val reached_merge = lastAction.name == "merge"
  val reached_detach = lastAction.name == "detach"
  val reached_close_linked = lastAction.name == "close_linked"
  val reached_linked_lost_access = lastAction.name == "linked_lost_access"

  def scenarioEditOk(c: Ctx, iid: str): bool = all {
    ["in_progress"].foldl(false, (acc, y994) => acc or y994 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_995) => acc or ((s_995.id == agentState(c.me)) and s_995.readOnly))),
  }

  /* ===== Мир модели ===== */

  pure val NOBODY = ""
  pure val DISPATCHER = "dispatcher"
  pure val SYSTEM = "system"
  // Три: основной с привязанным объединяется с третьим — relinkToPrimary
  pure val IDS: List[str] = ["i1", "i2", "i3"]
  pure val INCIDENTS: Set[str] = Set("i1", "i2", "i3")
  pure val OPERATOR_LIST: List[str] = ["a", "b"]
  pure val OPERATORS: Set[str] = Set("a", "b")
  // Две дежурные группы: уровень 2 эскалации — не та группа, куда уходит вышедший адресат уровня 1, — так
  // ветка «вышел — его группе» отличима от «пропустить уровень» (RULE-100, PROC-50). Порядок — как у машины
  pure val GROUP = "g"
  pure val GROUP2 = "h"
  pure val GROUP_LIST: List[str] = [GROUP, GROUP2]
  pure val GROUPS: Set[str] = Set(GROUP, GROUP2)
  pure val TARGETS: Set[str] = OPERATORS.union(GROUPS)
  // Сценарий без графа (§14.5): два сценария, у каждого два шага по порядку; пройден — отвечены оба (набор closing)
  pure val SCENARIOS: Set[str] = Set("fire", "water")
  pure val STEPS: Set[str] = Set("s1", "s2")
  // Сценарий модели — линейный: s1, затем s2, он финальный. Ответ — только на следующий неотвеченный шаг, поэтому
  // ответы — начало пути, и перенос объединением (shareAnswers) даёт то же, что настоящий перенос «по пути до
  // разрыва» (scenario.js, share); сверка ядра повторяет ответы и переносы на настоящем исполнителе (Р9 б, PROC-79)
  pure val STEP_ORDER: List[str] = ["s1", "s2"]
  // События (§14.5, ARCH-15): у инцидента — своё событие или общее ev0, выбор из двух. Так бывают и соседи — инциденты
  // общего события разных сценариев, — и три инцидента одного сценария, все с разными событиями: без них нет двух
  // привязанных к одному основному (premise_twoLinked), а при двух событиях на всех их быть не может. Выбор правила по
  // событию — вне модели: инцидент появляется сразу с событием и сценарием, модель проверяет ключ «событие +
  // сценарий» (intake.uniqueKey машины)
  pure val OWN_EVENT: str -> str = Map("i1" -> "ev1", "i2" -> "ev2", "i3" -> "ev3")
  pure val SHARED_EVENT = "ev0"
  pure def eventsFor(i: str): Set[str] = Set(OWN_EVENT.get(i), SHARED_EVENT)
  pure val PRIORITIES: Set[int] = Set(100, 50)
  // Часы с секунды: 0 у дедлайна и момента в машине — «нет»
  pure val START = 1000

  // Права и доступ выбираются при старте и меняются действием окружения «сменились роли» (§5)
  type Config = {
    perms: str -> Set[str],
    access: str -> Set[str],        // оператор → инциденты, к объектам которых у него доступ
    members: str -> Set[str],       // дежурная группа → участники
  }

  var cfg: Config
  var settings: Settings
  var world: World
  var clock: int
  // Состояние оператора (session машины): ready, not_ready (перерыв), offline (вышел); признак активности
  var agents: str -> str
  var lastBeat: str -> int
  // Связь интерфейса с сервером: пока есть, интерфейс сам присылает признак активности (heartbeatSec)
  var link: str -> bool
  // Момент последнего перехода инцидента — ядру: переход по молчанию не раньше него (RULE-48, BUG-76)
  var changedAt: str -> int
  var lastAction: Action
  // Сколько автоматических переходов у инцидента подряд — без действий людей и окружения, только со временем (П3, PROC-45)
  var autoRun: str -> int
  // Состояние до последнего шага — для свойств права на действие и двух соседних состояний (PROC-73). Пишет каждое
  // действие: prev' = snapshot; после init — само начальное состояние
  type Before = { world: World, cfg: Config, agents: str -> str, lastBeat: str -> int, link: str -> bool, clock: int }
  var prev: Before
  def snapshot: Before = { world: world, cfg: cfg, agents: agents, lastBeat: lastBeat, link: link, clock: clock }

  /* ===== Факты мира (cel.world машины) ===== */

  // Право действует, если набор прав проходит §10.3: с «Взять» или «Принять» нужен хотя бы один выход из карточки,
  // иначе эти права не действуют (EXIT_RULE из машины, PROC-73). Проверка при входе — в модели действует всегда.
  // При заданном лимите отложенных «Отложить» выходом не считается: лимит может его закрыть (RULE-136)
  pure def exitsFor(holdLimited: bool): Set[str] = if (holdLimited) EXIT_RULE.requiresAnyOfWithHoldLimit else EXIT_RULE.requiresAnyOf
  pure def permsAct(ps: Set[str], perm: str, holdLimited: bool): bool = all {
    ps.contains(perm),
    not(EXIT_RULE.disables.contains(perm) and EXIT_RULE.appliesTo.exists(p => ps.contains(p)) and not(exitsFor(holdLimited).exists(p => ps.contains(p)))),
  }
  def holdLimited: bool = settings.limits.maxOnHold > 0
  def can(who: str, perm: str): bool = OPERATORS.contains(who) and permsAct(cfg.perms.get(who), perm, holdLimited)
  def access(who: str, x: Incident): bool = OPERATORS.contains(who) and cfg.access.get(who).contains(x.id)
  def isOperator(id: str): bool = OPERATORS.contains(id)
  def isGroup(id: str): bool = GROUPS.contains(id)
  def members(g: str): List[str] = if (isGroup(g)) OPERATOR_LIST.select(m => cfg.members.get(g).contains(m)) else []
  def dutyGroups: List[str] = GROUP_LIST
  // Кому вообще можно передавать: люди и дежурные группы (§8.1, BUG-85)
  def transferTargets: List[str] = OPERATOR_LIST.concat(GROUP_LIST)
  // Групп устройств в модели нет: строк overrides по sourceGroup в машине тоже нет
  def inSourceGroup(x: Incident, g: str): bool = false
  // Условия правил по группе (§14.5, ARCH-15): групп устройств в модели нет — устройство ни в одной, глубина 0
  def deviceInGroup(d: str, g: str): bool = false
  def groupDepth(g: str): int = 0
  def agentState(who: str): str = if (OPERATORS.contains(who)) agents.get(who) else "offline"
  def idleSec(who: str): int = if (OPERATORS.contains(who)) (clock - lastBeat.get(who)) / 1000 else 0
  def nextStep(i: str): str = STEP_ORDER.foldl("", (n, s) => if (n == "" and not(world.answers.get(i).contains(s))) s else n)
  def stepsFilled(x: Incident, setId: str): bool = setId == "none" or (setId == "closing" and world.answers.get(x.id) == STEPS)

  // Перенос ответов при объединении (действие мира shareAnswers): отвеченные шаги основного — с ответами привязанного
  pure def shareAnswers(w: World, src: str, dst: str): World =
    if (INCIDENTS.contains(dst)) { ...w, answers: w.answers.set(dst, w.answers.get(dst).union(w.answers.get(src))) } else w
  // Инциденты сервера по порядку — те, что появились
  pure def incs(w: World): List[Incident] = IDS.foldl([], (acc, j) => if (w.inc.get(j).state != "") acc.append(w.inc.get(j)) else acc)
  // Видимость (§5, invariants.actorSeesIncident): действует только тот, у кого доступ к объекту
  def sees(a: str, i: str): bool = cfg.access.get(a).contains(i)
  def incOf(i: str): Incident = world.inc.get(i)
  pure def act0(kind: str, name: str, actor: str, i: str): Action =
    { name: name, actor: actor, incident: i, kind: kind, form: NO_FORM, surface: "", others: [], prio: 0, scenario: "", event: "" }

  /* ===== Ядро исполнения (CEL.md, «Ядро исполнения») — как у исполнителя прототипа prototype/engine.js ===== */

  def ctx(me: str, actor: str, form: Form, surface: str): Ctx =
    { me: me, actor: actor, now: clock, deadline: clock, form: form, surface: surface, before: NO_INCIDENT }
  pure def tr(tid: str): Transition = TRANSITIONS.select(t => t.id == tid)[0]
  pure def ofTrigger(trigger: str): List[Transition] = TRANSITIONS.select(t => t.trigger == trigger)

  // Переход по таймеру и системный: от чьего имени условия — у scope incidents_owned_by_agent владелец
  // (его исполнитель), иначе actor перехода
  def autoCtx(t: Transition, i: str): Ctx = ctx(if (t.ownedByAgent) incOf(i).owner else t.actor, t.actor, NO_FORM, "")
  def autoReady(t: Transition, i: str): bool = all {
    incOf(i).state != "",
    not(t.ownedByAgent) or OPERATORS.contains(incOf(i).owner),
    trOk(t.id, autoCtx(t, i), i),
  }
  // Момент перехода (RULE-41): по таймеру — дедлайн, по молчанию — порог, системный без них — сейчас
  def moment(t: Transition, i: str): int =
    if (t.timer != "") incOf(i).timers.get(t.timer).due
    else if (t.idleSec > 0) {
      val m = lastBeat.get(incOf(i).owner) + t.idleSec * 1000
      if (m > changedAt.get(i)) m else changedAt.get(i)
    }
    else clock
  def systemReadyFor(i: str): bool = ofTrigger("system").foldl(false, (acc, t) => acc or autoReady(t, i))
  // Выполняется сейчас: системный — сразу; по таймеру — после окна manualWinsOverTimer, а при готовом
  // системном — сразу, первым, если наступил раньше (RULE-41, RULE-67)
  def eligible(t: Transition, i: str, sys: bool): bool = all {
    t.trigger == "timer" or t.trigger == "system",
    autoReady(t, i),
    moment(t, i) <= clock,
    t.trigger == "system" or sys or moment(t, i) + GRACE_MS <= clock,
  }
  // Первый из готовых: раньше момент, при равенстве — по порядку в машине
  def nextAuto(i: str): List[Transition] = {
    val sys = systemReadyFor(i)
    AUTO.foldl([], (best, t) =>
      if (not(eligible(t, i, sys))) best
      else if (best.length() == 0 or moment(t, i) < moment(best[0], i)) [t]
      else best)
  }
  pure val AUTO: List[Transition] = TRANSITIONS.select(t => t.trigger == "timer" or t.trigger == "system")
  // Сервер выполняет автоматические переходы сразу: пока такой есть, шаг — только он (step), ни ручных
  // действий, ни времени. Действия ниже этого не проверяют — их можно вызывать и сами по себе (сценарии)
  def urgent: bool = INCIDENTS.exists(i => nextAuto(i).length() > 0)

  // Окно после дедлайна (§10.1, правило 5; RULE-63): ручное действие отменяет готовый переход по таймеру,
  // если таймер после действия не продолжается (continuesOn, RULE-83); первым — с более ранним дедлайном
  def canceledBy(tid: str, i: str): List[Transition] =
    ofTrigger("timer").foldl([], (best, t) =>
      if (not(all {
        autoReady(t, i),
        moment(t, i) <= clock,
        clock < moment(t, i) + GRACE_MS,
        not(CONTINUES_ON.get(t.timer).contains(tid)),
      })) best
      else if (best.length() == 0 or moment(t, i) < moment(best[0], i)) [t]
      else best)
  pure def markFired(w: World, i: str, timer: str): World = {
    val x = w.inc.get(i)
    { ...w, inc: w.inc.set(i, { ...x, timers: x.timers.set(timer, { ...x.timers.get(timer), fired: x.timers.get(timer).due }) }) }
  }
  // До действия: срабатывание отмечено; после — нарушение отменённого перехода его же recordBreach,
  // на момент дедлайна и на адресата до действия
  def windowStart(canceled: List[Transition], i: str, w: World): World =
    if (canceled.length() > 0) markFired(w, i, canceled[0].timer) else w
  def windowEnd(canceled: List[Transition], i: str, before: Incident, w: World): World =
    if (canceled.length() > 0) {
      val t = canceled[0]
      windowBreach(t.id, { ...ctx(DISPATCHER, DISPATCHER, NO_FORM, ""), deadline: before.timers.get(t.timer).due, before: before }, i, w)
    } else w

  // Действие оператора — признак активности (§12.3, BUG-76): кто действует, тот не молчит
  action commit(a: Action, w: World): bool = all {
    world' = w,
    changedAt' = INCIDENTS.mapBy(j => if (w.inc.get(j) != world.inc.get(j)) clock else changedAt.get(j)),
    lastBeat' = if (OPERATORS.contains(a.actor) and (a.kind == "manual" or a.kind == "merge" or a.kind == "merge_auto" or a.name == "answer")) lastBeat.set(a.actor, clock) else lastBeat,
    cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, link' = link,
    lastAction' = a,
    prev' = snapshot,
    // Автоматический переход — ещё один подряд; любое другое действие счёт сбрасывает (П3)
    autoRun' = if (a.kind == "auto") autoRun.set(a.incident, autoRun.get(a.incident) + 1) else INCIDENTS.mapBy(j => 0),
  }

  /* ===== Появление инцидента (переход с trigger event) ===== */

  // Инцидент события ev со сценарием sc (§14.5, ARCH-15). Правило уже выбрано — от него сценарий и приоритет; сам
  // выбор правила по событию — вне модели. Ключ intake.uniqueKey машины — событие + сценарий: второго инцидента того
  // же сценария на событие нет, повтор события и пересекающиеся правила его не дают
  def createOk(i: str, ev: str, sc: str): bool = all {
    incOf(i).state == "",
    not(INCIDENTS.exists(j => incOf(j).state != "" and incOf(j).eventGuid == ev and incOf(j).scenario == sc)),
  }
  action create(i: str, ev: str, sc: str, prio: int): bool = {
    val t = ofTrigger("event")[0]
    val w0 = { ...world,
      inc: world.inc.set(i, { ...NO_INCIDENT, id: i, number: i, eventType: "fire", priority: prio, occurredAt: clock, scenario: sc, eventGuid: ev }),
      answers: world.answers.set(i, Set()) }
    all {
      createOk(i, ev, sc),
      commit({ ...act0("create", t.id, DISPATCHER, i), prio: prio, scenario: sc, event: ev }, trApply(t.id, ctx(DISPATCHER, DISPATCHER, NO_FORM, ""), i, w0)),
    }
  }

  /* ===== Ручное действие (§6.1): условия перехода, видимость, окно после дедлайна ===== */

  action manual(a: str, tid: str, i: str, form: Form, surface: str): bool = {
    val t = tr(tid)
    val c = ctx(a, a, form, surface)
    val canceled = canceledBy(tid, i)
    val before = incOf(i)
    all {
      t.trigger == "manual",
      not(t.bulkOnly),
      t.surfaces.contains(surface),
      sees(a, i),
      trOk(tid, c, i),
      // Значения полей-списков — по правилам формы машины, как проверяет сервер (ARCH-09)
      formOk(tid, c, i),
      commit({ ...act0("manual", tid, a, i), form: form, surface: surface }, windowEnd(canceled, i, before, trApply(tid, c, i, windowStart(canceled, i, world)))),
    }
  }

  /* ===== «Взять в работу» на выборке (§11): merge на каждом, кроме основного, и takeWith на основном ===== */

  // kind — merge: основного назвал оператор (primaryGuid); merge_auto — основного выбрал сервер
  action mergeAs(kind: str, a: str, p: str, others: Set[str]): bool = {
    val list = IDS.select(j => others.contains(j))
    val cm = ctx(a, a, { ...NO_FORM, primaryId: p }, "")
    val take = tr(TAKE_WITH)
    val taking = take.from.contains(incOf(p).state)
    val ct = ctx(a, a, NO_FORM, "")
    // Окна — у каждого объединяемого и у основного, если его берут (BUG-62): до всех эффектов
    val canceled = list.foldl(Map(), (m, o) => m.put(o, canceledBy(MERGE, o)))
    val pc = if (taking) canceledBy(TAKE_WITH, p) else []
    val before = world.inc
    val w1 = list.foldl(world, (w, o) => windowStart(canceled.get(o), o, w))
    val w2 = windowStart(pc, p, w1)
    val w3 = list.foldl(w2, (w, o) => trApply(MERGE, cm, o, w))
    val w4 = list.foldl(w3, (w, o) => windowEnd(canceled.get(o), o, before.get(o), w))
    val w5 = if (taking) windowEnd(pc, p, before.get(p), trApply(TAKE_WITH, ct, p, w4)) else w4
    all {
      list.length() > 0,
      not(others.contains(p)),
      sees(a, p),
      others.forall(o => sees(a, o)),
      others.forall(o => trOk(MERGE, cm, o)),
      not(taking) or trOk(TAKE_WITH, ct, p),
      commit({ ...act0(kind, MERGE, a, p), others: list }, w5),
    }
  }
  // Основного выбирает сервер по mergePrimary машины (§11, ARCH-08 в1); назвать его клиент не может (RULE-101)
  action mergeAuto(a: str, sel: Set[str]): bool = {
    val ps = mergePrimary(IDS.select(j => sel.contains(j)).foldl([], (acc, j) => acc.append(incOf(j))), a)
    all { ps.length() == 1, mergeAs("merge_auto", a, ps[0].id, sel.exclude(Set(ps[0].id))) }
  }
  // Для сценариев: объединение, в котором сервер выбирает основным именно p
  action merge(a: str, p: str, others: Set[str]): bool = {
    val sel = others.union(Set(p))
    val ps = mergePrimary(IDS.select(j => sel.contains(j)).foldl([], (acc, j) => acc.append(incOf(j))), a)
    all { ps.length() == 1, ps[0].id == p, mergeAs("merge_auto", a, p, others.exclude(Set(p))) }
  }

  /* ===== Автоматические переходы: планировщик ===== */

  action fire(i: str): bool = {
    val nx = nextAuto(i)
    all {
      nx.length() > 0,
      {
        val t = nx[0]
        val due = if (t.timer != "") incOf(i).timers.get(t.timer).due else clock
        val w0 = if (t.timer != "") markFired(world, i, t.timer) else world
        commit(act0("auto", t.id, t.actor, i), trApply(t.id, { ...autoCtx(t, i), deadline: due }, i, w0))
      },
    }
  }

  /* ===== Окружение ===== */

  // Время — к следующему событию: дедлайн, миг после него (внутри окна), конец окна, порог молчания, конец срока
  // переоткрытия
  def events: Set[int] = INCIDENTS.filter(i => incOf(i).state != "").fold(Set(), (s, i) => {
    val x = incOf(i)
    val ds = TIMER_IDS.filter(k => x.timers.get(k).due != 0).map(k => x.timers.get(k).due)
    s.union(ds).union(ds.map(d => d + 1)).union(ds.map(d => d + GRACE_MS))
      .union(if (x.closedAt != 0) Set(x.closedAt + settings.limits.reopenWindowMin * 60000 + 1) else Set())
  }).union(OPERATORS.filter(o => agents.get(o) != "offline" and not(link.get(o))).fold(Set(), (s, o) =>
    s.union(Set(lastBeat.get(o) + settings.session.idleHoldSec * 1000, lastBeat.get(o) + settings.session.idleReleaseSec * 1000))))
  def futureEvents: Set[int] = events.filter(t => t > clock)
  action time: bool = {
    val nextAt = futureEvents.fold(clock, (m, t) => if (m == clock or t < m) t else m)
    all {
      futureEvents.size() > 0,
      world' = world, cfg' = cfg, settings' = settings, agents' = agents, link' = link, changedAt' = changedAt,
      // Пока связь есть, признак активности приходит и дальше
      lastBeat' = OPERATORS.mapBy(o => if (link.get(o) and agents.get(o) != "offline") nextAt else lastBeat.get(o)),
      clock' = nextAt,
      lastAction' = act0("time", "time", NOBODY, NOBODY),
      prev' = snapshot,
      autoRun' = autoRun,
    }
  }

  action agent(a: str, name: str, state: str, beat: bool): bool = all {
    agents' = agents.set(a, state),
    lastBeat' = if (beat) lastBeat.set(a, clock) else lastBeat,
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
    prev' = snapshot,
    autoRun' = INCIDENTS.mapBy(j => 0),
  }
  // Смена состояния оператора — переход session.transitions машины (AGENT_MOVES, ARCH-08 в4): откуда, куда, право
  // у состояния, куда переходят. На перерыве и после выхода — только просмотр (agentReady машины)
  pure def agentMoveOf(id: str): { id: str, from: Set[str], to: str, permission: str } =
    AGENT_MOVES.fold({ id: "", from: Set(), to: "", permission: "" }, (acc, m) => if (m.id == id) m else acc)
  action agentMove(a: str, id: str): bool = {
    val m = agentMoveOf(id)
    all {
      m.from.contains(agents.get(a)),
      m.permission == "" or can(a, m.permission),
      agent(a, m.id, m.to, true),
    }
  }
  action goOnBreak(a: str): bool = agentMove(a, "break")
  action backFromBreak(a: str): bool = agentMove(a, "back")
  action signOut(a: str): bool = agentMove(a, "sign_out")
  action signIn(a: str): bool = agentMove(a, "sign_in")
  // Пропала и вернулась связь (§12.3): без неё оператор молчит; вернулась — признак активности сразу
  action loseLink(a: str): bool = all {
    link.get(a),
    link' = link.set(a, false),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, lastBeat' = lastBeat, changedAt' = changedAt,
    lastAction' = act0("env", "lose_link", a, NOBODY),
    prev' = snapshot,
    autoRun' = INCIDENTS.mapBy(j => 0),
  }
  action restoreLink(a: str): bool = all {
    not(link.get(a)),
    link' = link.set(a, true),
    lastBeat' = lastBeat.set(a, clock),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, changedAt' = changedAt,
    lastAction' = act0("env", "restore_link", a, NOBODY),
    prev' = snapshot,
    autoRun' = INCIDENTS.mapBy(j => 0),
  }

  // Запрос оператора, который ничего не изменил, — отказанный переход, подсчёт выборки: тоже признак активности.
  // Любой запрос, кроме чтения (§12.3, BUG-76 а), RULE-112); нужна связь
  action request(a: str): bool = all {
    link.get(a),
    lastBeat' = lastBeat.set(a, clock),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", "request", a, NOBODY),
    prev' = snapshot,
    autoRun' = INCIDENTS.mapBy(j => 0),
  }

  // Сменились роли (§5): доступ к объекту инцидента, право «Принимать»
  action roles(a: str, name: str, c: Config): bool = all {
    cfg' = c,
    world' = world, settings' = settings, clock' = clock, agents' = agents, lastBeat' = lastBeat, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
    prev' = snapshot,
    autoRun' = INCIDENTS.mapBy(j => 0),
  }
  action toggleAccess(a: str, i: str): bool = {
    val s = cfg.access.get(a)
    roles(a, "toggle_access", { ...cfg, access: cfg.access.set(a, if (s.contains(i)) s.exclude(Set(i)) else s.union(Set(i))) })
  }
  action toggleAccept(a: str): bool = {
    val s = cfg.perms.get(a)
    roles(a, "toggle_accept", { ...cfg, perms: cfg.perms.set(a, if (s.contains("incident:accept")) s.exclude(Set("incident:accept")) else s.union(Set("incident:accept"))) })
  }

  // Ответ на шаг сценария (§10.4): кто может — scenarioEdit машины; шаг — следующий неотвеченный (линейный сценарий)
  action answer(a: str, i: str, st: str): bool = all {
    sees(a, i),
    scenarioEditOk(ctx(a, a, NO_FORM, "card"), i),
    st != "",
    st == nextStep(i),
    commit(act0("env", "answer", a, i), { ...world, answers: world.answers.set(i, world.answers.get(i).union(Set(st))) }),
  }

  /* ===== Начало и шаг =====
     Два профиля (PROC-72). Широкий — init и step: права, доступ и группы любые, роли меняются на ходу.
     «Смена» — initWork: типовые наборы прав валидатора, доступ ко всем инцидентам, в группе g оба; шаг
     stepWork — без смены ролей и пустых запросов, ответ на шаг сценария и закрытие с результатом, которому нужен
     пройденный сценарий, выпадают чаще. Редкие переходы и посылки инвариантов набирают историй в «смене»,
     переходы по доступу и праву «Принимать» — в широком (tools/check_quint_coverage.mjs) */

  action init = {
    nondet perms = OPERATORS.setOfMaps(USED_PERMISSIONS.powerset()).oneOf()
    nondet access = OPERATORS.setOfMaps(INCIDENTS.powerset()).oneOf()
    nondet grp = OPERATORS.powerset().oneOf()
    initFrom(perms, access, grp)
  }
  action initWork = {
    nondet perms = OPERATORS.setOfMaps(TYPICAL_PERMISSION_SETS).oneOf()
    initFrom(perms, OPERATORS.mapBy(a => INCIDENTS), OPERATORS)
  }
  // Уровень эскалации с адресатом t: вид — по адресату (человек или дежурная группа)
  pure def levelTo(l: Level, n: int, t: str): Level = { ...l, level: n, targetKind: if (GROUPS.contains(t)) "group" else "user", target: t }
  action initFrom(perms: str -> Set[str], access: str -> Set[str], grp: Set[str]): bool = {
    nondet grp2 = OPERATORS.powerset().oneOf()
    // Настройки, от которых зависят ветки автоматических переходов, — из машины (BRANCH_SETTINGS, PROC-43)
    nondet branch = BRANCH_SETTINGS.oneOf()
    nondet maxActive = Set(0, 1).oneOf()
    nondet maxOnHold = Set(0, 1).oneOf()
    // Состав уровней эскалации и потолок (§8.3, PROC-74): два или три уровня, адресат каждого — любой человек или
    // дежурная группа модели, потолок — от 1 до числа уровней; третий уровень — с нормативом второго
    nondet t1 = TARGETS.oneOf()
    nondet t2 = TARGETS.oneOf()
    nondet t3 = TARGETS.oneOf()
    nondet three = Set(false, true).oneOf()
    nondet starts = OPERATORS.setOfMaps(AGENT_STARTS).oneOf()
    val levels = MACHINE_SETTINGS.escalation.levels
    val chosen = [levelTo(levels[0], 1, t1), levelTo(levels[1], 2, t2)].concat(if (three) [levelTo(levels[1], 3, t3)] else [])
    nondet maxLevel = 1.to(chosen.length()).oneOf()
    val c = { perms: perms, access: access, members: Map(GROUP -> grp, GROUP2 -> grp2) }
    val w = { inc: INCIDENTS.mapBy(i => NO_INCIDENT), answers: INCIDENTS.mapBy(i => Set()) }
    all {
      cfg' = c,
      // Настройки — значения машины; перебираются ветки автоматики (withBranches), лимиты и состав уровней
      // эскалации, люди — люди модели; алерты — группе g
      settings' = withBranches({ ...MACHINE_SETTINGS,
        escalation: { ...MACHINE_SETTINGS.escalation, levels: chosen, maxLevel: maxLevel },
        alerts: { ...MACHINE_SETTINGS.alerts, targetKind: "group", target: GROUP },
        limits: { ...MACHINE_SETTINGS.limits, maxActive: maxActive, maxOnHold: maxOnHold },
      }, branch),
      world' = w,
      clock' = START,
      // Оператор — ещё не вошёл (начальное машины) или уже вошёл (RULE-99)
      agents' = starts,
      lastBeat' = OPERATORS.mapBy(a => START),
      link' = OPERATORS.mapBy(a => true),
      changedAt' = INCIDENTS.mapBy(i => 0),
      lastAction' = act0("init", "init", NOBODY, NOBODY),
      autoRun' = INCIDENTS.mapBy(i => 0),
      prev' = { world: w, cfg: c, agents: starts, lastBeat: OPERATORS.mapBy(a => START), link: OPERATORS.mapBy(a => true), clock: START },
    }
  }

  pure val MANUAL_IDS: Set[str] = ofTrigger("manual").foldl(Set(), (s, t) => if (t.bulkOnly) s else s.union(Set(t.id)))
  def pendingAuto: Set[str] = INCIDENTS.filter(i => nextAuto(i).length() > 0)
  action step = if (pendingAuto.size() > 0) fireAny else stepFree
  action stepWork = if (pendingAuto.size() > 0) fireAny else stepFreeWork
  action fireAny = {
    nondet j = pendingAuto.oneOf()
    fire(j)
  }
  action stepFree = {
    nondet i = INCIDENTS.oneOf()
    nondet a = OPERATORS.oneOf()
    any {
      createAny(i),
      manualAny(a, i, MANUAL_IDS, CLOSE_RESULT_IDS),
      mergeAny(a),
      time,
      agentMoveAny(a),
      loseLink(a),
      restoreLink(a),
      request(a),
      toggleAccess(a, i),
      toggleAccept(a),
      answerAny(a, i),
    }
  }
  action stepFreeWork = {
    nondet i = INCIDENTS.oneOf()
    nondet a = OPERATORS.oneOf()
    any {
      createAny(i),
      manualAny(a, i, MANUAL_IDS, CLOSE_RESULT_IDS),
      mergeAny(a),
      time,
      agentMoveAny(a),
      loseLink(a),
      restoreLink(a),
      // Ответ — двумя ветками, закрытие по пройденному сценарию — своей: иначе путь «ответы → закрыть» почти
      // не выпадает (замер PROC-72: 0 историй из 3000, с этими ветками — 27)
      answerAny(a, i),
      answerAny(a, i),
      manualAny(a, i, STEP_RESULT_CLOSE_IDS, STEP_RESULT_IDS),
    }
  }
  action createAny(i: str): bool = {
    nondet ev = eventsFor(i).oneOf()
    nondet sc = SCENARIOS.oneOf()
    nondet prio = PRIORITIES.oneOf()
    create(i, ev, sc, prio)
  }
  action manualAny(a: str, i: str, tids: Set[str], results: Set[str]): bool = {
    nondet tid = tids.oneOf()
    nondet target = TARGETS.oneOf()
    nondet reason = HOLD_REASONS_BY_OPERATOR.oneOf()
    nondet result = results.oneOf()
    nondet surface = tr(tid).surfaces.oneOf()
    val form = { ...NO_FORM, targetId: target, reasonId: reason, resultId: result,
      causeId: if (CAUSE_FOR.keys().contains(result)) CAUSE_FOR.get(result) else "", comment: "c" }
    manual(a, tid, i, form, surface)
  }
  action mergeAny(a: str): bool = {
    nondet sel = INCIDENTS.powerset().oneOf()
    mergeAuto(a, sel)
  }
  action agentMoveAny(a: str): bool = {
    nondet m = AGENT_MOVES.oneOf()
    agentMove(a, m.id)
  }
  action answerAny(a: str, i: str): bool = answer(a, i, nextStep(i))

  /* ===== Инварианты =====
     quint run im.qnt --invariant inv; каждый можно проверить отдельно — имена ниже.
     Инварианты пишутся руками и нарочно другими словами, чем правила машины: совпади они с машиной
     дословно, они бы ничего не проверяли. */

  pure val OPEN: Set[str] = Set("new", "pending_acceptance", "in_progress", "on_hold")
  pure def runs(t: Timer): bool = t.due != 0
  def isDueT(t: Timer): bool = t.due != 0 and t.due <= clock and t.fired != t.due
  pure def hasBreach(x: Incident, kind: str): bool = x.breaches.select(b => b.kind == kind).length() > 0
  def primaryOf(x: Incident): Incident = if (INCIDENTS.contains(x.linkedTo)) incOf(x.linkedTo) else NO_INCIDENT
  // Сейчас выполнится один из названных автоматических переходов этого инцидента — тот, что исправляет состояние
  // (PROC-73): не любой готовый, иначе случайно готовый таймер прикрыл бы запрещённое состояние
  def fixReady(i: str, names: Set[str]): bool = AUTO.foldl(false, (acc, t) => acc or (names.contains(t.id) and autoReady(t, i)))

  // 1. Владелец по состоянию (§2.1)
  val ownerByState = INCIDENTS.forall(i => {
    val x = incOf(i)
    val s = x.state
    if (s == "new" or s == "linked") x.owner == NOBODY and x.assignmentGroup == NOBODY
    else if (s == "pending_acceptance")
      (OPERATORS.contains(x.owner) and x.assignmentGroup == NOBODY) or (x.owner == NOBODY and GROUPS.contains(x.assignmentGroup))
    else if (s == "in_progress" or s == "on_hold") OPERATORS.contains(x.owner) and x.assignmentGroup == NOBODY
    // Закрытый — у того, кто закрыл; закрытый вместе с основным (close_linked) — у закрывшего основной (BUG-89)
    else if (s == "closed")
      OPERATORS.contains(x.closedBy) and x.assignmentGroup == NOBODY and x.owner == x.closedBy
    else s == ""
  })

  // 2. Причина удержания задана ⇔ «Отложен»
  val holdReasonIffOnHold = INCIDENTS.forall(i => (incOf(i).holdReasonId != NOBODY) iff (incOf(i).state == "on_hold"))

  // 3. Таймеры по состоянию (startsOnEnter, stopsOnEnter, pausedInStates). Реакция в «Новое» и «Ожидает
  //    принятия» остановлена только после записанного нарушения (RULE-84); сработавшая реакция не идёт дальше;
  //    наступивший дедлайн норматива закрытия не уходит на паузу необработанным
  val timersByState = INCIDENTS.forall(i => {
    val x = incOf(i)
    val r = x.timers.get("reaction")
    val z = x.timers.get("resolution")
    val h = x.timers.get("hold")
    val s = x.state
    all {
      not(runs(r) and r.fired == r.due),
      if (s == "new" or s == "pending_acceptance") not(runs(h)) and not(runs(z)) and (runs(r) or hasBreach(x, "reaction"))
      else if (s == "in_progress") runs(z) and not(runs(r)) and not(runs(h))
      // Срок удержания у причины есть всегда (§4, правило 7; RULE-135) — идёт он или уже нарушен, проверяет holdBounded
      else if (s == "on_hold") not(runs(z)) and z.paused and not(runs(r))
      else if (s == "closed") not(runs(r)) and not(runs(z)) and not(runs(h))
      // Свой норматив закрытия привязанного на паузе: у группы один срок — срок основного (RULE-97)
      else if (s == "linked") not(runs(r)) and not(runs(h)) and not(runs(z))
      else true,
    }
  })

  // 3б. Удержание не бесконечно (§4, правило 7; RULE-118): у отложенного идёт срок удержания или уже записано
  //     нарушение удержания — иначе отложенный лежал бы без срока, пока его не тронет человек
  val holdBounded = INCIDENTS.forall(i => {
    val x = incOf(i)
    x.state == "on_hold" implies (runs(x.timers.get("hold")) or hasBreach(x, "hold"))
  })

  // 3а. Наступивший дедлайн норматива закрытия не уходит на паузу необработанным: на паузе с остатком 0 —
  //     только отработанный (RULE-50); и у отсоединённого после наступившего срока группы (BUG-75)
  val dueNotPausedUnprocessed = INCIDENTS.forall(i => {
    val z = incOf(i).timers.get("resolution")
    not(z.paused and z.left == 0 and z.fired == 0)
  })

  // 4. Уровень эскалации в пределах (§8.3)
  val levelBounded = INCIDENTS.forall(i => incOf(i).escalationLevel >= 0 and incOf(i).escalationLevel <= settings.escalation.maxLevel)

  // 5. Результат закрытия задан ⇔ «Закрыто» (§2.2)
  //    Закрытие снимается «Переоткрыть» целиком: время, закрывший и комментарий — только у закрытого (RULE-103)
  val closeResultIffClosed = INCIDENTS.forall(i => {
    val x = incOf(i)
    val closed = x.state == "closed"
    all { (x.closeResultId != NOBODY) iff closed, (x.closedAt != 0) iff closed, (x.closedBy != NOBODY) iff closed, closed or x.result == "" }
  })

  // 6. По инциденту готово не больше одного перехода по таймеру (§14.3)
  val timerTransitionsExclusive = INCIDENTS.forall(i => ofTrigger("timer").select(t => autoReady(t, i)).length() <= 1)

  // 7. Наступивший дедлайн идущего таймера кто-то обрабатывает — не теряется молча (§4, §9)
  val dueDeadlineHandled = INCIDENTS.forall(i => {
    val x = incOf(i)
    TIMER_IDS.exists(k => isDueT(x.timers.get(k))) implies ofTrigger("timer").foldl(false, (acc, t) => acc or autoReady(t, i))
  })

  // 8. Лимиты (§10.2): maxOnHold ограничивает только ручное «Отложить» — системные удержания откладывают и сверх
  def countOwned(a: str, s: str): int = INCIDENTS.filter(j => incOf(j).state == s and incOf(j).owner == a).size()
  def countManualHeld(a: str): int =
    INCIDENTS.filter(j => incOf(j).state == "on_hold" and incOf(j).owner == a and HOLD_REASONS_BY_OPERATOR.contains(incOf(j).holdReasonId)).size()
  val limitsRespected = OPERATORS.forall(a => all {
    settings.limits.maxActive == 0 or countOwned(a, "in_progress") <= settings.limits.maxActive,
    settings.limits.maxOnHold == 0 or countManualHeld(a) <= settings.limits.maxOnHold,
  })

  // 9. У ожидающего принятия адресат может принять (§8.1) — или его сейчас снимает системный переход: права меняются
  def mayAccept(who: str, x: Incident): bool =
    if (isGroup(who)) cfg.members.get(who).exists(m => can(m, "incident:accept") and access(m, x))
    else can(who, "incident:accept") and access(who, x)
  val pendingAddresseeCanAccept = INCIDENTS.forall(i => {
    val x = incOf(i)
    val who = if (x.owner != NOBODY) x.owner else x.assignmentGroup
    x.state == "pending_acceptance" implies (mayAccept(who, x) or fixReady(i, Set("addressee_cannot_accept", "addressee_lost_access")))
  })

  // 10. Эскалация не адресует инцидент тому, у кого он уже есть: тому же человеку, той же группе или группе,
  //     где принять может только его владелец (§8.1, §8.3, RULE-93)
  def escalatesToCurrent(tid: str, i: str): bool = {
    val x = incOf(i)
    val who = if (x.owner != NOBODY) x.owner else x.assignmentGroup
    val t = levelUpTarget(x)
    autoReady(tr(tid), i) and (t == who or (isGroup(t) and not(cfg.members.get(t).exists(m => m != x.owner and can(m, "incident:accept") and access(m, x)))))
  }
  val autoEscalateNotToCurrentAddressee = INCIDENTS.forall(i => not(escalatesToCurrent("auto_escalate", i)))
  val resolutionEscalateNotToCurrentAddressee = INCIDENTS.forall(i => not(escalatesToCurrent("resolution_escalate", i)))

  // 11. Эскалация не отдаёт инцидент туда, где принять сейчас некому: вышедшему человеку, у которого в дежурной
  //     группе никто не на месте, кто может принять, и группе, где вышли все, кто может принять (§8.3, RULE-100)
  def presentAcceptor(m: str, x: Incident): bool =
    agentState(m) != "offline" and m != x.owner and can(m, "incident:accept") and access(m, x)
  def escalatesToNobody(tid: str, i: str): bool = {
    val x = incOf(i)
    val t = levelUpTarget(x)
    val g = dutyGroupOf(t)
    val nobody =
      if (isGroup(t)) not(cfg.members.get(t).exists(m => presentAcceptor(m, x)))
      else agentState(t) == "offline" and not(g != "" and cfg.members.get(g).exists(m => m != t and presentAcceptor(m, x)))
    autoReady(tr(tid), i) and t != "" and nobody
  }
  val autoEscalateToSomeone = INCIDENTS.forall(i => not(escalatesToNobody("auto_escalate", i)))
  val resolutionEscalateToSomeone = INCIDENTS.forall(i => not(escalatesToNobody("resolution_escalate", i)))

  // 11. Форма связи (§11.3, §11.4): у привязанного нет причины удержания и результата; основной — другой
  //     инцидент, сам не привязан и открыт; закрытый — привязанный сейчас закроется вместе с ним
  val linkedShape = INCIDENTS.forall(i => {
    val x = incOf(i)
    val p = primaryOf(x)
    x.state == "linked" implies all {
      x.holdReasonId == NOBODY,
      x.closeResultId == NOBODY,
      INCIDENTS.contains(x.linkedTo),
      x.linkedTo != i,
      OPEN.contains(p.state) or (p.state == "closed" and fixReady(i, Set("close_linked"))),
    }
  })

  // 12. Открытый ни к чему не привязан: отсоединение и переоткрытие снимают связь (BUG-42)
  val openNotLinked = INCIDENTS.forall(i => OPEN.contains(incOf(i).state) implies incOf(i).linkedTo == NOBODY)

  // 13. У нарушения закрытия есть чьё: срок группы идёт, только пока основной кто-то ведёт (RULE-97)
  val resolutionBreachHasOwner = INCIDENTS.forall(i => incOf(i).breaches.select(b => b.kind == "resolution" and b.owner == NOBODY).length() == 0)

  // 14. Нарушения основного по срокам после присоединения — и у привязанного (§11.4, RULE-97, BUG-73)
  val linkedSharesBreaches = INCIDENTS.forall(i => {
    val x = incOf(i)
    x.state == "linked" implies primaryOf(x).breaches.select(b => b.at > x.linkedAt).foldl(true, (acc, b) =>
      acc and x.breaches.foldl(false, (f, y) => f or y == b))
  })

  // 15. Ни один инцидент не остаётся у того, у кого нет к нему доступа (§5, RULE-71): у адресата открытого —
  //     доступ к нему, у адресата основного — и к привязанным; иначе его сейчас снимает системный переход
  def reach(who: str, x: Incident): bool =
    if (isGroup(who)) cfg.members.get(who).exists(m => access(m, x)) else access(who, x)
  val noIncidentWithoutAccess = INCIDENTS.forall(i => {
    val x = incOf(i)
    val p = primaryOf(x)
    val who = if (x.owner != NOBODY) x.owner else x.assignmentGroup
    val pwho = if (p.owner != NOBODY) p.owner else p.assignmentGroup
    all {
      Set("pending_acceptance", "in_progress", "on_hold").contains(x.state) implies (reach(who, x) or fixReady(i, Set("addressee_lost_access"))),
      (x.state == "linked" and p.state != "closed" and pwho != NOBODY) implies (reach(pwho, x) or fixReady(i, Set("linked_lost_access")) or fixReady(x.linkedTo, Set("addressee_lost_access"))),
    }
  })

  // 16. Автоматический переход не повторяется сразу же: выполненный — больше не готов в тот же момент, иначе
  //     планировщик ходил бы по кругу, а время стояло
  val autoNotRepeated = INCIDENTS.forall(i => {
    val nx = nextAuto(i)
    not(nx.length() > 0 and lastAction.incident == i and lastAction.name == nx[0].id)
  })

  // 17. Привязанный — того же сценария, что основной (§11.3)
  val linkedSameScenario = INCIDENTS.forall(i => incOf(i).state == "linked" implies incOf(i).scenario == primaryOf(incOf(i)).scenario)

  // 18. «Обработан» своим «Закрыть» — только у пройденного сценария, в том числе за счёт ответов, перенесённых
  //     при объединении (§2.2, §14.5); закрытый вместе с основным берёт его результат (§11.4)
  val processedOnlyFinished = INCIDENTS.forall(i => {
    val x = incOf(i)
    (x.state == "closed" and x.closeResultId == "processed" and x.linkedTo == NOBODY) implies world.answers.get(i) == STEPS
  })

  // 19. Вышедший не держит ни своих, ни лично ему адресованных (§8.1, §12.1); на перерыве у оператора нет
  //     инцидентов «В работе» (§12.2) — или их сейчас снимает системный переход
  val agentStateRespected = INCIDENTS.forall(i => {
    val x = incOf(i)
    all {
      (Set("pending_acceptance", "in_progress", "on_hold").contains(x.state) and agentState(x.owner) == "offline" and OPERATORS.contains(x.owner))
        implies fixReady(i, Set("owner_signed_out", "addressee_signed_out_to_group", "addressee_signed_out_to_queue")),
      (x.state == "in_progress" and agentState(x.owner) == "not_ready") implies fixReady(i, Set("system_hold_break")),
    }
  })

  // 12. П1. Наступивший дедлайн обработан не позже окна после него: часы не уходят за дедлайн + graceSec, пока
  //     срабатывание не выполнено — ни реакция, ни удержание не висят просроченными без нарушения (§4, §10.1, PROC-45)
  val deadlineFiredInWindow = INCIDENTS.forall(i => TIMER_IDS.forall(k => {
    val t = incOf(i).timers.get(k)
    isDueT(t) implies clock <= t.due + GRACE_MS
  }))

  // 13. П2. Молчащий владелец, который не вышел (§12.3): «В работе» при молчании от idleHoldSec — сейчас
  //     откладывается; отложенный системой (причины, которые оператор сам не выбирает) при молчании от
  //     idleReleaseSec — сейчас уходит в очередь (PROC-45); отложенный оператором молчание в очередь не возвращает —
  //     причина по справочнику, а не по условию перехода (PROC-87)
  val silentOwnerHandled = INCIDENTS.forall(i => {
    val x = incOf(i)
    val idle = if (OPERATORS.contains(x.owner) and agentState(x.owner) != "offline") idleSec(x.owner) else 0
    all {
      (x.state == "in_progress" and idle >= settings.session.idleHoldSec) implies fixReady(i, Set("system_hold_idle")),
      (x.state == "on_hold" and x.holdReasonId != NOBODY and not(HOLD_REASONS_BY_OPERATOR.contains(x.holdReasonId)) and idle >= settings.session.idleReleaseSec) implies fixReady(i, Set("system_release_idle")),
      (lastAction.incident == i and lastAction.name == "system_release_idle") implies not(HOLD_REASONS_BY_OPERATOR.contains(before(i).holdReasonId)),
    }
  })

  // 14. П3. Без людей автоматика конечна: подряд, только со временем, у инцидента — не больше AUTO_BOUND
  //     автоматических переходов; эскалация упирается в потолок, круга нет. Самая длинная цепочка — около 8,
  //     например resolution_overdue → system_hold_idle → hold_overdue → system_release_idle → auto_escalate → …
  //     → escalation_ceiling; при пределе 3 модель находит нарушение — у предела есть запас, но не лишний (PROC-45)
  pure val AUTO_BOUND = 10
  val autoBounded = INCIDENTS.forall(i => autoRun.get(i) <= AUTO_BOUND)

  // 20. Право на действие (§6.1, §2.2, §10.1, правило 2; PROC-73): ручной переход и объединение сделал тот, у
  //     кого до шага (prev) были право и условие, — оператор на месте, видел инцидент, а дальше по переходу
  def hadPerm(a: str, p: str): bool = prev.cfg.perms.get(a).contains(p)
  def hadAccess(a: str, i: str): bool = prev.cfg.access.get(a).contains(i)
  // Адресат — я или дежурная группа, где я состою (§8.1)
  def wasAddressee(a: str, x: Incident): bool =
    x.owner == a or (GROUPS.contains(x.assignmentGroup) and prev.cfg.members.get(x.assignmentGroup).contains(a))
  def rightFor(a: str, tid: str, x0: Incident, x: Incident): bool =
    if (tid == "claim") x0.state == "new" and hadPerm(a, "incident:claim")
    else if (tid == "accept") x0.state == "pending_acceptance" and wasAddressee(a, x0) and hadPerm(a, "incident:accept")
    else if (tid == "reject") x0.state == "pending_acceptance" and wasAddressee(a, x0) and hadPerm(a, "incident:release")
    else if (tid == "hold") x0.state == "in_progress" and x0.owner == a and hadPerm(a, "incident:hold")
    else if (tid == "resume") x0.state == "on_hold" and x0.owner == a and hadPerm(a, "incident:claim")
    else if (tid == "release") Set("in_progress", "on_hold").contains(x0.state) and x0.owner == a and hadPerm(a, "incident:release")
    // Передать (§5): своё — новый, мой или адресованный мне или моей группе — правом own, остальное — правом any
    else if (tid == "transfer")
      if (x0.state == "new" or x0.owner == a or (x0.state == "pending_acceptance" and wasAddressee(a, x0))) hadPerm(a, "incident:transfer:own")
      else hadPerm(a, "incident:transfer:any")
    else if (tid == "takeover") not(wasAddressee(a, x0)) and hadPerm(a, "incident:reassign") and hadPerm(a, "incident:claim")
    // Закрыть (§2.2): «Массовый сбой» — своим правом и ещё из «Новое» и «Ожидает принятия», остальные — из «В
    // работе»; в работе и отложенный — только свой
    else if (tid == "close") all {
      if (x.closeResultId == "mass") hadPerm(a, "incident:close:unprocessed") else hadPerm(a, "incident:close") and x0.state == "in_progress",
      Set("in_progress", "on_hold").contains(x0.state) implies x0.owner == a,
    }
    else if (tid == "reopen") all {
      x0.state == "closed",
      prev.clock - x0.closedAt <= settings.limits.reopenWindowMin * 60000,
      hadPerm(a, "incident:reopen"),
      hadPerm(a, "incident:claim"),
    }
    // Отсоединить (§11.4, RULE-78): я веду основной — он мой, в работе или отложен, — или основной новый и ничей;
    // у основного «Ожидает принятия» — только после «Принять»
    else if (tid == "detach") {
      val p0 = prev.world.inc.get(x0.linkedTo)
      x0.state == "linked" and ((p0.state == "new" and p0.owner == NOBODY and p0.assignmentGroup == NOBODY)
        or (Set("in_progress", "on_hold").contains(p0.state) and p0.owner == a))
    }
    else true
  // 21. Свойства двух соседних состояний (PROC-73): инцидент сейчас и до шага (prev)
  def before(i: str): Incident = prev.world.inc.get(i)

  //     а) Передачей и отклонением реакцию не продлить (§6.1, RULE-82, RULE-83): после «Передать» из «Новое» и
  //        «Ожидает принятия», «Отклонить» и ухода вышедшего адресата срок реакции прежний, если она шла.
  //        Остановленную потолком или нарушением «Передать» запускает заново, «Отклонить» — нет (RULE-84).
  //        «Вернуть в очередь», выход владельца и «Отсоединить» продолжают реакцию с остатка, запомненного при взятии
  //        или объединении: цикл «взял — вернул» эскалацию не откладывает (RULE-104, RULE-121, RULE-128; PROC-84)
  val reactionNotExtended = {
    val la = lastAction
    val r0 = before(la.incident).timers.get("reaction")
    val r = incOf(la.incident).timers.get("reaction")
    val keeps = (la.name == "transfer" and Set("new", "pending_acceptance").contains(before(la.incident).state))
      or Set("reject", "addressee_signed_out_to_group", "addressee_signed_out_to_queue").contains(la.name)
    INCIDENTS.contains(la.incident) implies all {
      (keeps and runs(r0)) implies r.due == r0.due,
      (la.name == "reject" and not(runs(r0))) implies not(runs(r)),
      (Set("release", "owner_signed_out", "detach").contains(la.name) and r0.paused and r0.left > 0) implies r.due == clock + r0.left,
    }
  }

  //     а2) Срок группы — самый ранний (§11.4, RULE-97; PROC-84): после объединения остаток норматива закрытия основного —
  //        наименьший из своего и неотработанных остатков объединённых; новый основной берётся с полного норматива, но
  //        не позже их. Наступивший срок основного (окно, нарушение) — по правилам окна, здесь не проверяется
  pure def remOf(z: Timer, now: int): int = if (z.due != 0) (if (z.due > now) z.due - now else 0) else if (z.paused) z.left else -1
  val groupDeadlineEarliest = {
    val la = lastAction
    val p0 = remOf(before(la.incident).timers.get("resolution"), clock)
    val p = remOf(incOf(la.incident).timers.get("resolution"), clock)
    val others = la.others.foldl([], (acc, o) => {
      val r = remOf(before(o).timers.get("resolution"), clock)
      if (r > 0) acc.append(r) else acc
    })
    val least = others.foldl(-1, (m, r) => if (m < 0 or r < m) r else m)
    Set("merge", "merge_auto").contains(la.kind) implies {
      if (p0 > 0) p == (if (least > 0 and least < p0) least else p0)
      else if (p0 < 0) p > 0 and (least > 0 implies p <= least)
      else true
    }
  }

  //     а2б) Вышедший из группы уносит срок группы (§11.4, §6.2; PROC-91): после «Отсоединить» и потери доступа
  //        (linked_lost_access) норматив закрытия на паузе с остатком основного на этот момент — не со своим прежним
  //        и не с полным: иначе взятый позже получил бы срок длиннее группы
  val leftGroupKeepsGroupDeadline = {
    val la = lastAction
    val z = incOf(la.incident).timers.get("resolution")
    val r = remOf(before(before(la.incident).linkedTo).timers.get("resolution"), clock)
    (INCIDENTS.contains(la.incident) and Set("detach", "linked_lost_access").contains(la.name) and r >= 0)
      implies (z.paused and z.due == 0 and z.left == r)
  }

  //     а3) Закрытый не меняется, пока его самого не переоткрыли (§2.1, §6.1; PROC-84): ни связь, ни сроки, ни владелец.
  //        Нарушение дописаться может: отсоединённый в окне после срока группы и закрытый в нём — был в группе в момент
  //        срока и получает её нарушение (BUG-73); что нарушения только дописываются — breachesKept
  val closedKept = INCIDENTS.forall(i =>
    (before(i).state == "closed" and not(lastAction.name == "reopen" and lastAction.incident == i))
      implies { ...incOf(i), breaches: before(i).breaches, slaBreached: before(i).slaBreached } == before(i))

  //     а4) Срок удержания — по причине (§4, правило 7; RULE-129, RULE-132; PROC-84): при входе в «Отложен» срок — сейчас
  //        плюс срок причины; у «Нет связи» (deadlineFromIdle) — порог возврата в очередь минус порог удержания, не
  //        меньше 0: срок причины и возврат по молчанию совпадают; причина без срока — срок не идёт
  val holdDeadlineByReason = INCIDENTS.forall(i => {
    val x = incOf(i)
    val h = x.timers.get("hold")
    val rs = settings.holdReasons.select(r => r.id == x.holdReasonId)
    val s = settings.session
    val sec = if (rs.length() == 0) -1
      else if (rs[0].deadlineFromIdle) (if (s.idleReleaseSec > s.idleHoldSec) s.idleReleaseSec - s.idleHoldSec else 0)
      else if (rs[0].maxMinutes.length() > 0) rs[0].maxMinutes[0] * 60
      else -1
    (before(i).state != "on_hold" and x.state == "on_hold") implies (if (sec >= 0) h.due == clock + sec * 1000 else not(runs(h)))
  })

  //     а5) Перерыв — только из «Готов» (§12.2; PROC-84): «Занят» в модели — тот же «Готов»; из «Вышел» — сначала вход
  val breakFromReady = (lastAction.kind == "env" and lastAction.name == "break")
    implies (prev.agents.get(lastAction.actor) == "ready" and agents.get(lastAction.actor) == "not_ready")

  //     а6) Норматив реакции уровня (§8.3, RULE-76; PROC-86): после автоэскалации реакция идёт с нормативом того
  //        уровня, на который инцидент поднялся, — по списку уровней, а не через levelNorm машины
  val escalationReactionNorm = {
    val la = lastAction
    val x = incOf(la.incident)
    val ls = settings.escalation.levels.select(l => l.level == x.escalationLevel)
    (INCIDENTS.contains(la.incident) and Set("auto_escalate", "resolution_escalate").contains(la.name))
      implies (ls.length() > 0 and x.timers.get("reaction").due == clock + ls[0].reactionSec * 1000)
  }

  //     б) Уровень эскалации меняет только эскалация этого инцидента, и только вверх (§8.3)
  val levelOnlyByEscalation = INCIDENTS.forall(i => {
    val l0 = before(i).escalationLevel
    val l = incOf(i).escalationLevel
    l != l0 implies all {
      lastAction.incident == i,
      Set("auto_escalate", "resolution_escalate").contains(lastAction.name),
      l > l0,
    }
  })

  //     в) Нарушения не стираются (§6.1, «Переоткрыть»; §10.1): записанные остаются в том же порядке, новые — в конец
  val breachesKept = INCIDENTS.forall(i => {
    val b0 = before(i).breaches
    val b = incOf(i).breaches
    if (b.length() >= b0.length()) b.slice(0, b0.length()) == b0 else false
  })

  //     г) Остаток норматива закрытия сохраняется (§4): «Отложить» запоминает, сколько осталось, «Возобновить»
  //        продолжает с того же остатка. Отработанный норматив (RULE-50) — другой случай, его здесь нет
  val resolutionLeftKept = {
    val la = lastAction
    val z0 = before(la.incident).timers.get("resolution")
    val z = incOf(la.incident).timers.get("resolution")
    INCIDENTS.contains(la.incident) implies all {
      (la.name == "hold" and runs(z0)) implies (z.paused and z.left == (if (z0.due > clock) z0.due - clock else 0)),
      (la.name == "resume" and z0.paused and z0.left > 0) implies z.due == clock + z0.left,
    }
  }

  //     д) Действие не создаёт состояния, которое система тут же исправляет (Р5 б): после ручного перехода и
  //        объединения у этого инцидента не готов ни один исправляющий системный переход
  pure val FIXERS: Set[str] = Set("addressee_cannot_accept", "addressee_lost_access", "close_linked", "linked_lost_access",
    "owner_signed_out", "addressee_signed_out_to_group", "addressee_signed_out_to_queue", "system_hold_break",
    "system_hold_idle", "system_release_idle")
  //        Исключения — по правилам: «Передать» вышедшему можно, инцидент сразу уходит его группе или в очередь
  //        (§8.1, «Адресат вышел»; RULE-47)
  pure def fixExpected(tid: str): Set[str] =
    if (tid == "transfer") Set("addressee_signed_out_to_group", "addressee_signed_out_to_queue") else Set()
  val noFixAfterAction =
    Set("manual", "merge", "merge_auto").contains(lastAction.kind)
      implies not(fixReady(lastAction.incident, FIXERS.exclude(fixExpected(lastAction.name))))

  // 22. Выход есть (§10.3; PROC-73): у «В работе», чей владелец на месте, видит инцидент и имеет право хотя бы на
  //     один выход, доступен хотя бы один выход из карточки — «Отложить», «Вернуть в очередь» или «Закрыть»
  pure def exitForm(reason: str, result: str): Form = { ...NO_FORM, reasonId: reason, resultId: result,
    causeId: if (CAUSE_FOR.keys().contains(result)) CAUSE_FOR.get(result) else "", comment: "c" }
  def exitOk(a: str, tid: str, i: str, f: Form): bool =
    tr(tid).surfaces.exists(s => trOk(tid, ctx(a, a, f, s), i) and formOk(tid, ctx(a, a, f, s), i))
  val exitExists = INCIDENTS.forall(i => {
    val x = incOf(i)
    val a = x.owner
    // Право на выход — по §10.3: при заданном лимите отложенных «Отложить» не в счёт (RULE-136)
    (x.state == "in_progress" and OPERATORS.contains(a) and agentState(a) == "ready" and sees(a, i)
      and exitsFor(holdLimited).exists(p => can(a, p))) implies or {
      HOLD_REASONS_BY_OPERATOR.exists(r => exitOk(a, "hold", i, exitForm(r, ""))),
      HOLD_REASONS_BY_OPERATOR.exists(r => exitOk(a, "release", i, exitForm(r, ""))),
      CLOSE_RESULT_IDS.exists(r => exitOk(a, "close", i, exitForm("", r))),
    }
  })

  // 23. Системный переход — только по делу (PROC-84): исправляющий переход сделан, только если до шага (prev) было что
  //     исправлять — адресат без доступа, не может принять, вышел; владелец вышел или на перерыве. Доступ и право
  //     принять у дежурной группы — у кого-то из участников (§5, §8.1)
  def hadPermOf(m: str, p: str): bool = permsAct(prev.cfg.perms.get(m), p, holdLimited)
  def reachedBefore(who: str, i: str): bool =
    if (GROUPS.contains(who)) prev.cfg.members.get(who).exists(m => hadAccess(m, i)) else OPERATORS.contains(who) and hadAccess(who, i)
  def couldAcceptBefore(who: str, i: str): bool =
    if (GROUPS.contains(who)) prev.cfg.members.get(who).exists(m => hadPermOf(m, "incident:accept") and hadAccess(m, i))
    else OPERATORS.contains(who) and hadPermOf(who, "incident:accept") and hadAccess(who, i)
  val systemOnlyWhenDue = {
    val la = lastAction
    val x0 = before(la.incident)
    val who = if (x0.owner != NOBODY) x0.owner else x0.assignmentGroup
    la.kind == "auto" implies (
      if (la.name == "addressee_lost_access") not(reachedBefore(who, la.incident))
      else if (la.name == "addressee_cannot_accept") not(couldAcceptBefore(who, la.incident))
      else if (la.name == "owner_signed_out") prev.agents.get(x0.owner) == "offline"
      else if (Set("addressee_signed_out_to_group", "addressee_signed_out_to_queue").contains(la.name)) OPERATORS.contains(x0.owner) and prev.agents.get(x0.owner) == "offline"
      else if (la.name == "system_hold_break") prev.agents.get(x0.owner) == "not_ready"
      else true
    )
  }

  val actionRights = {
    val la = lastAction
    val a = la.actor
    val x0 = prev.world.inc.get(la.incident)
    // Объединение (§11.3): право на выборку, каждый — ничей или мой, у каждого доступ
    val mergeOk = hadPerm(a, "incident:bulk") and la.others.foldl(true, (ok, o) => ok and hadAccess(a, o) and
      Set(NOBODY, a).contains(prev.world.inc.get(o).owner)) and Set(NOBODY, a).contains(x0.owner)
    Set("manual", "merge", "merge_auto").contains(la.kind) implies all {
      prev.agents.get(a) == "ready",
      hadAccess(a, la.incident),
      if (la.kind == "manual") rightFor(a, la.name, x0, incOf(la.incident)) else mergeOk,
    }
  }

  // 24. Ключ «событие + сценарий» (§14.5, ARCH-15; oneIncidentPerEventScenario машины): у двух появившихся инцидентов
  //     одного события сценарии разные — повтор события и пересекающиеся правила второго инцидента сценария не дают
  val eventScenarioUnique = INCIDENTS.forall(i => INCIDENTS.forall(j => {
    val x = incOf(i)
    val y = incOf(j)
    (i != j and x.state != "" and y.state != "" and x.eventGuid == y.eventGuid) implies x.scenario != y.scenario
  }))

  // 25. Соседи — не привязка §11 (§14.5): у привязанного событие другое, чем у основного. Следствие linkedSameScenario
  //     и eventScenarioUnique — страховка на случай, если одно из них ослабнет
  val siblingsNotLinked = INCIDENTS.forall(i => incOf(i).linkedTo != NOBODY implies incOf(i).eventGuid != primaryOf(incOf(i)).eventGuid)

  val inv = all {
    ownerByState,
    holdReasonIffOnHold,
    timersByState,
    holdBounded,
    dueNotPausedUnprocessed,
    levelBounded,
    closeResultIffClosed,
    timerTransitionsExclusive,
    dueDeadlineHandled,
    limitsRespected,
    pendingAddresseeCanAccept,
    autoEscalateNotToCurrentAddressee,
    resolutionEscalateNotToCurrentAddressee,
    autoEscalateToSomeone,
    resolutionEscalateToSomeone,
    linkedShape,
    openNotLinked,
    resolutionBreachHasOwner,
    linkedSharesBreaches,
    noIncidentWithoutAccess,
    autoNotRepeated,
    linkedSameScenario,
    processedOnlyFinished,
    agentStateRespected,
    deadlineFiredInWindow,
    silentOwnerHandled,
    autoBounded,
    actionRights,
    reactionNotExtended,
    groupDeadlineEarliest,
    leftGroupKeepsGroupDeadline,
    systemOnlyWhenDue,
    closedKept,
    holdDeadlineByReason,
    breakFromReady,
    escalationReactionNorm,
    levelOnlyByEscalation,
    breachesKept,
    resolutionLeftKept,
    noFixAfterAction,
    exitExists,
    eventScenarioUnique,
    siblingsNotLinked,
  }

  /* ===== Свидетели посылок (PROC-72) =====
     Посылка инварианта выполнилась — иначе он в прогоне ничего не проверяет. Вместе с reached_<переход> их
     считает tools/check_quint_coverage.mjs: каждый — не меньше чем в 20 историях */

  // processedOnlyFinished: закрыт своим «Закрыть» с результатом «Обработан»
  val premise_processedClosed = INCIDENTS.exists(i => incOf(i).state == "closed" and incOf(i).closeResultId == "processed" and incOf(i).linkedTo == NOBODY)
  // holdBounded, вторая ветка: отложенный с записанным нарушением удержания
  val premise_holdBreach = INCIDENTS.exists(i => incOf(i).state == "on_hold" and hasBreach(incOf(i), "hold"))
  // Два привязанных к одному основному (linkedShape, linkedSharesBreaches, linkedSameScenario)
  val premise_twoLinked = INCIDENTS.exists(p => INCIDENTS.filter(i => incOf(i).linkedTo == p).size() >= 2)
  // Соседи — два появившихся инцидента одного события (eventScenarioUnique)
  val premise_siblings = INCIDENTS.exists(i => INCIDENTS.exists(j => i != j and incOf(i).state != "" and incOf(j).state != "" and incOf(i).eventGuid == incOf(j).eventGuid))
}
