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
  // (tools/check_quint_replay.mjs). others — набор объединения, prio и scenario — у появления
  type Action = { name: str, actor: str, incident: str, kind: str, form: Form, surface: str, others: List[str], prio: int, scenario: str }

  /* ===== Типы машины (cel.types) ===== */


  type Incident = { id: str, number: str, eventType: str, priority: int, occurredAt: int, state: str, owner: str, assignmentGroup: str, holdReasonId: str, escalationLevel: int, transferCount: int, closeResultId: str, closeCauseId: str, result: str, closedBy: str, closedAt: int, slaBreached: bool, breaches: List[Breach], timers: str -> Timer, linkedTo: str, linkedAt: int, leftGroup: LeftGroup, scenario: str }

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

  type Override = { eventType: List[str], priority: List[int], sourceGroup: List[str], sec: int }

  type HoldReason = { id: str, maxMinutes: List[int], setBy: str, deadlineFromIdle: bool }

  type Settings = { limits: Limits, session: Session, escalation: Escalation, alerts: Alerts, states: List[State], closeResults: List[CloseResultItem], timerDefs: List[TimerDef], holdReasons: List[HoldReason] }


  /* ===== Настройки — значения машины (cel.settings) ===== */


  pure val MACHINE_SETTINGS: Settings = {
    limits: { maxActive: 0, maxOnHold: 5, maxBulk: 0, reopenWindowMin: 1440, reopenResolutionSec: 0 },
    session: { states: [{ id: "ready", readOnly: false, readOnlyReasonKey: "" }, { id: "busy", readOnly: false, readOnlyReasonKey: "" }, { id: "not_ready", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.not_ready" }, { id: "offline", readOnly: true, readOnlyReasonKey: "workflow.session.readonly.offline" }], heartbeatSec: 30, idleHoldSec: 300, idleReleaseSec: 1200 },
    escalation: { enabled: true, levels: [{ level: 1, targetKind: "user", target: "petrova", reactionSec: 120 }, { level: 2, targetKind: "user", target: "noc", reactionSec: 90 }], maxLevel: 2, onResolutionOverdue: "alert" },
    alerts: { targetKind: "group", target: "grp-leads", noRecipientLog: "workflow.journal.alert_no_recipient" },
    states: [{ id: "new", category: "pending" }, { id: "pending_acceptance", category: "pending" }, { id: "in_progress", category: "active" }, { id: "on_hold", category: "active" }, { id: "closed", category: "done" }, { id: "linked", category: "linked" }],
    closeResults: [{ id: "processed", labelKey: "workflow.catalog.close_result.processed", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "closing", commentRequired: false, finish: true }, { id: "false_alarm", labelKey: "workflow.catalog.close_result.false_alarm", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "duplicate", labelKey: "workflow.catalog.close_result.duplicate", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "drill", labelKey: "workflow.catalog.close_result.drill", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "impossible", labelKey: "workflow.catalog.close_result.impossible", permission: "incident:close", fromStates: ["in_progress"], ownerOnlyInStates: ["in_progress"], surfaces: ["card"], requiredStepSet: "none", commentRequired: true, finish: false }, { id: "mass", labelKey: "workflow.catalog.close_result.mass", permission: "incident:close:unprocessed", fromStates: ["new", "pending_acceptance", "in_progress", "on_hold"], ownerOnlyInStates: ["in_progress", "on_hold"], surfaces: ["queue", "card"], requiredStepSet: "none", commentRequired: true, finish: false }],
    timerDefs: [{ id: "reaction", labelKey: "workflow.timer.reaction", defaultSec: 300, byPriority: Map(), overridesBy: ["eventType", "priority", "sourceGroup"], overrides: [{ eventType: [], priority: [100], sourceGroup: [], sec: 240 }, { eventType: [], priority: [75], sourceGroup: [], sec: 420 }, { eventType: [], priority: [50], sourceGroup: [], sec: 900 }, { eventType: [], priority: [25], sourceGroup: [], sec: 1800 }], keepsLeft: true, startsOnce: false, pausable: false, secFrom: "" }, { id: "resolution", labelKey: "workflow.timer.resolution", defaultSec: 900, byPriority: Map(25 -> 1800, 50 -> 1500, 75 -> 900, 100 -> 600), overridesBy: ["eventType", "priority", "sourceGroup"], overrides: [], keepsLeft: false, startsOnce: true, pausable: true, secFrom: "" }, { id: "hold", labelKey: "workflow.timer.hold", defaultSec: 0, byPriority: Map(), overridesBy: [], overrides: [], keepsLeft: false, startsOnce: false, pausable: false, secFrom: "reasonCatalogs.hold[].maxMinutes" }],
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

  pure val EXIT_RULE: { appliesTo: Set[str], requiresAnyOf: Set[str], disables: Set[str] } = { appliesTo: Set("incident:claim", "incident:accept"), requiresAnyOf: Set("incident:hold", "incident:release", "incident:close"), disables: Set("incident:claim", "incident:accept") }

  pure val USED_PERMISSIONS: Set[str] = Set("agent:set_not_ready", "incident:accept", "incident:bulk", "incident:claim", "incident:close", "incident:close:unprocessed", "incident:hold", "incident:reassign", "incident:release", "incident:reopen", "incident:run_action", "incident:transfer:any", "incident:transfer:own")

  pure val TIMER_IDS: Set[str] = Set("reaction", "resolution", "hold")

  pure val NO_TIMER: Timer = { due: 0, paused: false, left: 0, fired: 0, since: 0 }

  pure val NO_INCIDENT: Incident = { ...{ id: "", number: "", eventType: "", priority: 0, occurredAt: 0, state: "", owner: "", assignmentGroup: "", holdReasonId: "", escalationLevel: 0, transferCount: 0, closeResultId: "", closeCauseId: "", result: "", closedBy: "", closedAt: 0, slaBreached: false, breaches: [], timers: Map(), linkedTo: "", linkedAt: 0, leftGroup: { primaryId: "", linkedAt: 0, at: 0 }, scenario: "" }, timers: Map("reaction" -> NO_TIMER, "resolution" -> NO_TIMER, "hold" -> NO_TIMER) }

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
    ((o.eventType.length() + o.priority.length()) + o.sourceGroup.length())

  def overrideMatches(x: Incident, o: Override): bool =
    ((((o.eventType.length() == 0) or (o.eventType[0] == x.eventType)) and ((o.priority.length() == 0) or (o.priority[0] == x.priority))) and ((o.sourceGroup.length() == 0) or inSourceGroup(x, o.sourceGroup[0])))

  // §4, правило 2. Строка уточнения учитывается, только если все её признаки — из overridesBy таймера (ARCH-11)

  def overrideAllowed(t: TimerDef, o: Override): bool =
    ((((o.eventType.length() == 0) or t.overridesBy.foldl(false, (acc, y39) => acc or y39 == "eventType")) and ((o.priority.length() == 0) or t.overridesBy.foldl(false, (acc, y40) => acc or y40 == "priority"))) and ((o.sourceGroup.length() == 0) or t.overridesBy.foldl(false, (acc, y41) => acc or y41 == "sourceGroup")))

  // §4, правило 2. Норматив, с: самая специфичная строка overrides (при равных — первая), иначе byPriority, иначе defaultSec

  def norm(x: Incident, t: TimerDef): int =
    { val ms_42 = t.overrides.select(o_43 => (overrideAllowed(t, o_43) and overrideMatches(x, o_43)))  (if ((ms_42.length() > 0)) ms_42.select(o_44 => ms_42.foldl(true, (acc, k_45) => acc and (overrideKeys(k_45) <= overrideKeys(o_44))))[0].sec else (if (t.byPriority.keys().contains(x.priority)) t.byPriority.get(x.priority) else t.defaultSec)) }

  // §4. Срок удержания, с — по причине (secFrom таймера hold). У причины с deadlineFromIdle («Нет связи») — порог возврата в очередь минус порог удержания, не меньше 0: срок причины и возврат по молчанию совпадают при любых порогах (RULE-118, RULE-129, RULE-132). Причины нет или у неё нет срока (maxMinutes: null) — -1, срок не ставится

  def holdSec(x: Incident): int =
    { val rs_46 = settings.holdReasons.select(r_47 => (r_47.id == x.holdReasonId))  (if ((rs_46.length() == 0)) (0 - 1) else (if (rs_46[0].deadlineFromIdle) (if ((settings.session.idleReleaseSec > settings.session.idleHoldSec)) (settings.session.idleReleaseSec - settings.session.idleHoldSec) else 0) else (if ((rs_46[0].maxMinutes.length() > 0)) (rs_46[0].maxMinutes[0] * 60) else (0 - 1)))) }

  // §8.3. Норматив реакции уровня автоэскалации: уровня нет — последний; уровень 0 — обычный норматив (RULE-76)

  def levelNorm(x: Incident): int =
    (if (((x.escalationLevel > 0) and (settings.escalation.levels.length() > 0))) { val ls_48 = settings.escalation.levels.select(l_49 => (l_49.level == x.escalationLevel))  (if ((ls_48.length() > 0)) ls_48[0].reactionSec else settings.escalation.levels[(settings.escalation.levels.length() - 1)].reactionSec) } else norm(x, timerDef("reaction")))

  // §4. Длительность таймера, с: из справочника (secFrom), по уровню эскалации или по нормативам

  def timerSec(x: Incident, id: str, mode: str): int =
    (if ((timerDef(id).secFrom != "")) holdSec(x) else (if ((mode == "byEscalationLevel")) levelNorm(x) else norm(x, timerDef(id))))

  // Остаток таймера, мс: идёт — до дедлайна, на паузе — остаток, не запускался — -1

  def leftOf(x: Incident, id: str, now: int): int =
    { val t_50 = x.timers.get(id)  (if ((t_50.due != 0)) (if (((t_50.due - now) > 0)) (t_50.due - now) else 0) else (if (t_50.paused) t_50.left else (0 - 1))) }

  // RULE-50. Норматив нарушен и отработан: остатка нет, дедлайн сработал

  def spent(x: Incident, id: str, now: int): bool =
    ((leftOf(x, id, now) == 0) and (x.timers.get(id).fired != 0))

  // §11.4, BUG-73, BUG-75. Был в группе основного p в момент at: открытый привязанный, присоединённый не позже, или вышедший не раньше

  def inGroupAt(e: Incident, p: Incident, at: int): bool =
    ((((e.linkedTo == p.id) and not(isDone(e))) and (e.linkedAt <= at)) or (((e.leftGroup.primaryId == p.id) and (e.leftGroup.linkedAt <= at)) and (e.leftGroup.at >= at)))

  // Инцидент по id — списком из одного или пустым

  def incidentById(incidents: List[Incident], id: str): List[Incident] =
    byId(incidents, id)

  // §11. Привязанные к основному id — и открытые, и закрытые вместе с ним

  def linkedOf(incidents: List[Incident], id: str): List[Incident] =
    incidents.select(e_51 => (e_51.linkedTo == id))

  // §10.2. Сколько инцидентов человека в состоянии, кроме одного — для лимитов

  def countMine(incidents: List[Incident], who: str, state: str, except: str): int =
    mineIn(incidents, who, state, except).length()

  // §10.2. Те же инциденты списком — для подсказки, кто держит лимит

  def mineOf(incidents: List[Incident], who: str, state: str, except: str): List[Incident] =
    mineIn(incidents, who, state, except)

  // §11.4. Кто был в группе основного p в момент at (inGroupAt)

  def groupMembersAt(incidents: List[Incident], p: Incident, at: int): List[Incident] =
    incidents.select(e_52 => ((e_52.id != p.id) and inGroupAt(e_52, p, at)))

  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */


  def ec_resumeTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w53 = if (not(timerDef(timerId).pausable)) {
      val sec_54 = timerSec(w0.inc.get(iid), timerId, "")
      val w55 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if ((sec_54 < 0)) 0 else (c.now + (sec_54 * 1000))) }) }) }
      val w56 = { ...w55, inc: w55.inc.set(iid, { ...w55.inc.get(iid), timers: w55.inc.get(iid).timers.set(timerId, { ...w55.inc.get(iid).timers.get(timerId), since: c.now }) }) }
      w56
    } else {
      val w57 = if ((w0.inc.get(iid).timers.get(timerId).due == 0)) {
      val left_58 = (if (w0.inc.get(iid).timers.get(timerId).paused) w0.inc.get(iid).timers.get(timerId).left else (timerSec(w0.inc.get(iid), timerId, "") * 1000))
      val w59 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: (if (((left_58 == 0) and (w0.inc.get(iid).timers.get(timerId).fired != 0))) w0.inc.get(iid).timers.get(timerId).fired else (c.now + left_58)) }) }) }
      val w60 = { ...w59, inc: w59.inc.set(iid, { ...w59.inc.get(iid), timers: w59.inc.get(iid).timers.set(timerId, { ...w59.inc.get(iid).timers.get(timerId), paused: false }) }) }
      val w61 = { ...w60, inc: w60.inc.set(iid, { ...w60.inc.get(iid), timers: w60.inc.get(iid).timers.set(timerId, { ...w60.inc.get(iid).timers.get(timerId), left: 0 }) }) }
      w61
    } else w0
      w57
    }
    w53
  }

  def ec_pauseTimer(w0: World, c: Ctx, iid: str, timerId: str): World = {
    val w62 = if (not(timerDef(timerId).pausable)) {
      val w63 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      val w64 = { ...w63, inc: w63.inc.set(iid, { ...w63.inc.get(iid), timers: w63.inc.get(iid).timers.set(timerId, { ...w63.inc.get(iid).timers.get(timerId), since: 0 }) }) }
      w64
    } else {
      val w65 = if ((w0.inc.get(iid).timers.get(timerId).due != 0)) {
      val w66 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set(timerId, { ...w0.inc.get(iid).timers.get(timerId), left: (if (((w0.inc.get(iid).timers.get(timerId).due - c.now) > 0)) (w0.inc.get(iid).timers.get(timerId).due - c.now) else 0) }) }) }
      val w67 = { ...w66, inc: w66.inc.set(iid, { ...w66.inc.get(iid), timers: w66.inc.get(iid).timers.set(timerId, { ...w66.inc.get(iid).timers.get(timerId), paused: true }) }) }
      val w68 = { ...w67, inc: w67.inc.set(iid, { ...w67.inc.get(iid), timers: w67.inc.get(iid).timers.set(timerId, { ...w67.inc.get(iid).timers.get(timerId), due: 0 }) }) }
      w68
    } else w0
      w65
    }
    w62
  }

  // create: event → new

  def ok_create(c: Ctx, iid: str): bool = all {
    world.inc.get(iid).state == "",
  }

  def e_create_0(w0: World, c: Ctx, iid: str): World = {
    val who_69 = ""
    val w70 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_69 }) }
    w70
  }

  def e_create_1(w0: World, c: Ctx, iid: str): World = {
    val group_71 = ""
    val w72 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_71 }) }
    w72
  }

  def e_create_2(w0: World, c: Ctx, iid: str): World = {
    val value_73 = 0
    val w74 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_73 }) }
    w74
  }

  def e_create_3(w0: World, c: Ctx, iid: str): World = {
    val w75 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w76 = if (timerDef("reaction").startsOnce) {
      val w77 = ec_resumeTimer(w0, c, iid, "reaction")
      w77
    } else {
      val w78 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w79 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w80 = { ...w79, inc: w79.inc.set(iid, { ...w79.inc.get(iid), timers: w79.inc.get(iid).timers.set("reaction", { ...w79.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w81 = { ...w80, inc: w80.inc.set(iid, { ...w80.inc.get(iid), timers: w80.inc.get(iid).timers.set("reaction", { ...w80.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w81
    } else {
      val sec_82 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w83 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_82 < 0)) 0 else (c.now + (sec_82 * 1000))) }) }) }
      val w84 = { ...w83, inc: w83.inc.set(iid, { ...w83.inc.get(iid), timers: w83.inc.get(iid).timers.set("reaction", { ...w83.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w85 = { ...w84, inc: w84.inc.set(iid, { ...w84.inc.get(iid), timers: w84.inc.get(iid).timers.set("reaction", { ...w84.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w86 = { ...w85, inc: w85.inc.set(iid, { ...w85.inc.get(iid), timers: w85.inc.get(iid).timers.set("reaction", { ...w85.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w86
    }
      w78
    }
      w76
    }
    w75
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
    not(settings.session.states.foldl(false, (acc, s_87) => acc or ((s_87.id == agentState(c.me)) and s_87.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_claim_0(w0: World, c: Ctx, iid: str): World = {
    val who_88 = c.actor
    val w89 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_88 }) }
    w89
  }

  def e_claim_1(w0: World, c: Ctx, iid: str): World = {
    val w90 = if (timerDef("reaction").startsOnce) {
      val w91 = ec_pauseTimer(w0, c, iid, "reaction")
      w91
    } else {
      val w92 = if (false) {
      val w93 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w94 = { ...w93, inc: w93.inc.set(iid, { ...w93.inc.get(iid), timers: w93.inc.get(iid).timers.set("reaction", { ...w93.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w95 = { ...w94, inc: w94.inc.set(iid, { ...w94.inc.get(iid), timers: w94.inc.get(iid).timers.set("reaction", { ...w94.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w96 = { ...w95, inc: w95.inc.set(iid, { ...w95.inc.get(iid), timers: w95.inc.get(iid).timers.set("reaction", { ...w95.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w96
    } else {
      val w97 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_98 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w99 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_98) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w100 = { ...w99, inc: w99.inc.set(iid, { ...w99.inc.get(iid), timers: w99.inc.get(iid).timers.set("reaction", { ...w99.inc.get(iid).timers.get("reaction"), paused: keep_98 }) }) }
      val w101 = { ...w100, inc: w100.inc.set(iid, { ...w100.inc.get(iid), timers: w100.inc.get(iid).timers.set("reaction", { ...w100.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w102 = { ...w101, inc: w101.inc.set(iid, { ...w101.inc.get(iid), timers: w101.inc.get(iid).timers.set("reaction", { ...w101.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w102
    }
      w97
    }
      w92
    }
    w90
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w103 = if (not(timerDef("resolution").pausable)) {
      val sec_104 = timerSec(w0.inc.get(iid), "resolution", "")
      val w105 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_104 < 0)) 0 else (c.now + (sec_104 * 1000))) }) }) }
      val w106 = { ...w105, inc: w105.inc.set(iid, { ...w105.inc.get(iid), timers: w105.inc.get(iid).timers.set("resolution", { ...w105.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w106
    } else {
      val w107 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_108 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w109 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_108 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_108)) }) }) }
      val w110 = { ...w109, inc: w109.inc.set(iid, { ...w109.inc.get(iid), timers: w109.inc.get(iid).timers.set("resolution", { ...w109.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w111 = { ...w110, inc: w110.inc.set(iid, { ...w110.inc.get(iid), timers: w110.inc.get(iid).timers.set("resolution", { ...w110.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w111
    } else w0
      w107
    }
    w103
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
    not(settings.session.states.foldl(false, (acc, s_112) => acc or ((s_112.id == agentState(c.me)) and s_112.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_113 = c.actor
    val w114 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_113 }) }
    w114
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_115 = ""
    val w116 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_115 }) }
    w116
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w117 = if (timerDef("reaction").startsOnce) {
      val w118 = ec_pauseTimer(w0, c, iid, "reaction")
      w118
    } else {
      val w119 = if (false) {
      val w120 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w121 = { ...w120, inc: w120.inc.set(iid, { ...w120.inc.get(iid), timers: w120.inc.get(iid).timers.set("reaction", { ...w120.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w122 = { ...w121, inc: w121.inc.set(iid, { ...w121.inc.get(iid), timers: w121.inc.get(iid).timers.set("reaction", { ...w121.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w123 = { ...w122, inc: w122.inc.set(iid, { ...w122.inc.get(iid), timers: w122.inc.get(iid).timers.set("reaction", { ...w122.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w123
    } else {
      val w124 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_125 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w126 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_125) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w127 = { ...w126, inc: w126.inc.set(iid, { ...w126.inc.get(iid), timers: w126.inc.get(iid).timers.set("reaction", { ...w126.inc.get(iid).timers.get("reaction"), paused: keep_125 }) }) }
      val w128 = { ...w127, inc: w127.inc.set(iid, { ...w127.inc.get(iid), timers: w127.inc.get(iid).timers.set("reaction", { ...w127.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w129 = { ...w128, inc: w128.inc.set(iid, { ...w128.inc.get(iid), timers: w128.inc.get(iid).timers.set("reaction", { ...w128.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w129
    }
      w124
    }
      w119
    }
    w117
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
    val w130 = if (not(timerDef("resolution").pausable)) {
      val sec_131 = timerSec(w0.inc.get(iid), "resolution", "")
      val w132 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_131 < 0)) 0 else (c.now + (sec_131 * 1000))) }) }) }
      val w133 = { ...w132, inc: w132.inc.set(iid, { ...w132.inc.get(iid), timers: w132.inc.get(iid).timers.set("resolution", { ...w132.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w133
    } else {
      val w134 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_135 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w136 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_135 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_135)) }) }) }
      val w137 = { ...w136, inc: w136.inc.set(iid, { ...w136.inc.get(iid), timers: w136.inc.get(iid).timers.set("resolution", { ...w136.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w138 = { ...w137, inc: w137.inc.set(iid, { ...w137.inc.get(iid), timers: w137.inc.get(iid).timers.set("resolution", { ...w137.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w138
    } else w0
      w134
    }
    w130
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
    not(settings.session.states.foldl(false, (acc, s_139) => acc or ((s_139.id == agentState(c.me)) and s_139.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_140 = ""
    val w141 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_140 }) }
    w141
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_142 = ""
    val w143 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_142 }) }
    w143
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
    not(settings.session.states.foldl(false, (acc, s_144) => acc or ((s_144.id == agentState(c.me)) and s_144.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_145 = c.form.reasonId
    val w146 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_145 }) }
    w146
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w147 = if (not(timerDef("resolution").pausable)) {
      val w148 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w149 = { ...w148, inc: w148.inc.set(iid, { ...w148.inc.get(iid), timers: w148.inc.get(iid).timers.set("resolution", { ...w148.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w149
    } else {
      val w150 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w151 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w152 = { ...w151, inc: w151.inc.set(iid, { ...w151.inc.get(iid), timers: w151.inc.get(iid).timers.set("resolution", { ...w151.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w153 = { ...w152, inc: w152.inc.set(iid, { ...w152.inc.get(iid), timers: w152.inc.get(iid).timers.set("resolution", { ...w152.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w153
    } else w0
      w150
    }
    w147
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w154 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w155 = if (timerDef("hold").startsOnce) {
      val w156 = ec_resumeTimer(w0, c, iid, "hold")
      w156
    } else {
      val w157 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w158 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w159 = { ...w158, inc: w158.inc.set(iid, { ...w158.inc.get(iid), timers: w158.inc.get(iid).timers.set("hold", { ...w158.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w160 = { ...w159, inc: w159.inc.set(iid, { ...w159.inc.get(iid), timers: w159.inc.get(iid).timers.set("hold", { ...w159.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w160
    } else {
      val sec_161 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w162 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_161 < 0)) 0 else (c.now + (sec_161 * 1000))) }) }) }
      val w163 = { ...w162, inc: w162.inc.set(iid, { ...w162.inc.get(iid), timers: w162.inc.get(iid).timers.set("hold", { ...w162.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w164 = { ...w163, inc: w163.inc.set(iid, { ...w163.inc.get(iid), timers: w163.inc.get(iid).timers.set("hold", { ...w163.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w165 = { ...w164, inc: w164.inc.set(iid, { ...w164.inc.get(iid), timers: w164.inc.get(iid).timers.set("hold", { ...w164.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w165
    }
      w157
    }
      w155
    }
    w154
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
    not(settings.session.states.foldl(false, (acc, s_166) => acc or ((s_166.id == agentState(c.me)) and s_166.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w167 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w167
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w168 = if (timerDef("hold").startsOnce) {
      val w169 = ec_pauseTimer(w0, c, iid, "hold")
      w169
    } else {
      val w170 = if (false) {
      val w171 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w172 = { ...w171, inc: w171.inc.set(iid, { ...w171.inc.get(iid), timers: w171.inc.get(iid).timers.set("hold", { ...w171.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w173 = { ...w172, inc: w172.inc.set(iid, { ...w172.inc.get(iid), timers: w172.inc.get(iid).timers.set("hold", { ...w172.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w174 = { ...w173, inc: w173.inc.set(iid, { ...w173.inc.get(iid), timers: w173.inc.get(iid).timers.set("hold", { ...w173.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w174
    } else {
      val w175 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_176 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w177 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_176) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w178 = { ...w177, inc: w177.inc.set(iid, { ...w177.inc.get(iid), timers: w177.inc.get(iid).timers.set("hold", { ...w177.inc.get(iid).timers.get("hold"), paused: keep_176 }) }) }
      val w179 = { ...w178, inc: w178.inc.set(iid, { ...w178.inc.get(iid), timers: w178.inc.get(iid).timers.set("hold", { ...w178.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w180 = { ...w179, inc: w179.inc.set(iid, { ...w179.inc.get(iid), timers: w179.inc.get(iid).timers.set("hold", { ...w179.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w180
    }
      w175
    }
      w170
    }
    w168
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w181 = if (not(timerDef("resolution").pausable)) {
      val sec_182 = timerSec(w0.inc.get(iid), "resolution", "")
      val w183 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_182 < 0)) 0 else (c.now + (sec_182 * 1000))) }) }) }
      val w184 = { ...w183, inc: w183.inc.set(iid, { ...w183.inc.get(iid), timers: w183.inc.get(iid).timers.set("resolution", { ...w183.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w184
    } else {
      val w185 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_186 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w187 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_186 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_186)) }) }) }
      val w188 = { ...w187, inc: w187.inc.set(iid, { ...w187.inc.get(iid), timers: w187.inc.get(iid).timers.set("resolution", { ...w187.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w189 = { ...w188, inc: w188.inc.set(iid, { ...w188.inc.get(iid), timers: w188.inc.get(iid).timers.set("resolution", { ...w188.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w189
    } else w0
      w185
    }
    w181
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
    not(settings.session.states.foldl(false, (acc, s_190) => acc or ((s_190.id == agentState(c.me)) and s_190.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_191 = ""
    val w192 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_191 }) }
    w192
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w193 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w193
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w194 = if (not(timerDef("resolution").pausable)) {
      val w195 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w196 = { ...w195, inc: w195.inc.set(iid, { ...w195.inc.get(iid), timers: w195.inc.get(iid).timers.set("resolution", { ...w195.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w196
    } else {
      val w197 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w198 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w199 = { ...w198, inc: w198.inc.set(iid, { ...w198.inc.get(iid), timers: w198.inc.get(iid).timers.set("resolution", { ...w198.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w200 = { ...w199, inc: w199.inc.set(iid, { ...w199.inc.get(iid), timers: w199.inc.get(iid).timers.set("resolution", { ...w199.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w200
    } else w0
      w197
    }
    w194
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w201 = if (timerDef("hold").startsOnce) {
      val w202 = ec_pauseTimer(w0, c, iid, "hold")
      w202
    } else {
      val w203 = if (false) {
      val w204 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w205 = { ...w204, inc: w204.inc.set(iid, { ...w204.inc.get(iid), timers: w204.inc.get(iid).timers.set("hold", { ...w204.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w206 = { ...w205, inc: w205.inc.set(iid, { ...w205.inc.get(iid), timers: w205.inc.get(iid).timers.set("hold", { ...w205.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w207 = { ...w206, inc: w206.inc.set(iid, { ...w206.inc.get(iid), timers: w206.inc.get(iid).timers.set("hold", { ...w206.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w207
    } else {
      val w208 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_209 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w210 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_209) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w211 = { ...w210, inc: w210.inc.set(iid, { ...w210.inc.get(iid), timers: w210.inc.get(iid).timers.set("hold", { ...w210.inc.get(iid).timers.get("hold"), paused: keep_209 }) }) }
      val w212 = { ...w211, inc: w211.inc.set(iid, { ...w211.inc.get(iid), timers: w211.inc.get(iid).timers.set("hold", { ...w211.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w213 = { ...w212, inc: w212.inc.set(iid, { ...w212.inc.get(iid), timers: w212.inc.get(iid).timers.set("hold", { ...w212.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w213
    }
      w208
    }
      w203
    }
    w201
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w214 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w215 = if (timerDef("reaction").startsOnce) {
      val w216 = ec_resumeTimer(w0, c, iid, "reaction")
      w216
    } else {
      val w217 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w218 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w219 = { ...w218, inc: w218.inc.set(iid, { ...w218.inc.get(iid), timers: w218.inc.get(iid).timers.set("reaction", { ...w218.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w220 = { ...w219, inc: w219.inc.set(iid, { ...w219.inc.get(iid), timers: w219.inc.get(iid).timers.set("reaction", { ...w219.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w220
    } else {
      val sec_221 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w222 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_221 < 0)) 0 else (c.now + (sec_221 * 1000))) }) }) }
      val w223 = { ...w222, inc: w222.inc.set(iid, { ...w222.inc.get(iid), timers: w222.inc.get(iid).timers.set("reaction", { ...w222.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w224 = { ...w223, inc: w223.inc.set(iid, { ...w223.inc.get(iid), timers: w223.inc.get(iid).timers.set("reaction", { ...w223.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w225 = { ...w224, inc: w224.inc.set(iid, { ...w224.inc.get(iid), timers: w224.inc.get(iid).timers.set("reaction", { ...w224.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w225
    }
      w217
    }
      w215
    }
    w214
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
    not(settings.session.states.foldl(false, (acc, s_226) => acc or ((s_226.id == agentState(c.me)) and s_226.readOnly))),
    transferTargets.foldl(false, (acc, t_227) => acc or (offersTransferTo(c.me, t_227, world.inc.get(iid)) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_228) => acc and (isDone(e_228) or hasAccess(t_227, e_228))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_229) => acc and (isDone(e_229) or hasAccess(c.form.targetId, e_229)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_230 = personOf(c.form.targetId)
    val w231 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_230 }) }
    w231
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_232 = groupOf(c.form.targetId)
    val w233 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_232 }) }
    w233
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w234 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w234
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w235 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w235
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w236 = if (not(timerDef("resolution").pausable)) {
      val w237 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w238 = { ...w237, inc: w237.inc.set(iid, { ...w237.inc.get(iid), timers: w237.inc.get(iid).timers.set("resolution", { ...w237.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w238
    } else {
      val w239 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w240 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w241 = { ...w240, inc: w240.inc.set(iid, { ...w240.inc.get(iid), timers: w240.inc.get(iid).timers.set("resolution", { ...w240.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w242 = { ...w241, inc: w241.inc.set(iid, { ...w241.inc.get(iid), timers: w241.inc.get(iid).timers.set("resolution", { ...w241.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w242
    } else w0
      w239
    }
    w236
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w243 = if (timerDef("hold").startsOnce) {
      val w244 = ec_pauseTimer(w0, c, iid, "hold")
      w244
    } else {
      val w245 = if (false) {
      val w246 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w247 = { ...w246, inc: w246.inc.set(iid, { ...w246.inc.get(iid), timers: w246.inc.get(iid).timers.set("hold", { ...w246.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w248 = { ...w247, inc: w247.inc.set(iid, { ...w247.inc.get(iid), timers: w247.inc.get(iid).timers.set("hold", { ...w247.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w249 = { ...w248, inc: w248.inc.set(iid, { ...w248.inc.get(iid), timers: w248.inc.get(iid).timers.set("hold", { ...w248.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w249
    } else {
      val w250 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_251 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w252 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_251) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w253 = { ...w252, inc: w252.inc.set(iid, { ...w252.inc.get(iid), timers: w252.inc.get(iid).timers.set("hold", { ...w252.inc.get(iid).timers.get("hold"), paused: keep_251 }) }) }
      val w254 = { ...w253, inc: w253.inc.set(iid, { ...w253.inc.get(iid), timers: w253.inc.get(iid).timers.set("hold", { ...w253.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w255 = { ...w254, inc: w254.inc.set(iid, { ...w254.inc.get(iid), timers: w254.inc.get(iid).timers.set("hold", { ...w254.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w255
    }
      w250
    }
      w245
    }
    w243
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w256 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w257 = if (timerDef("reaction").startsOnce) {
      val w258 = ec_resumeTimer(w0, c, iid, "reaction")
      w258
    } else {
      val w259 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w260 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w261 = { ...w260, inc: w260.inc.set(iid, { ...w260.inc.get(iid), timers: w260.inc.get(iid).timers.set("reaction", { ...w260.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w262 = { ...w261, inc: w261.inc.set(iid, { ...w261.inc.get(iid), timers: w261.inc.get(iid).timers.set("reaction", { ...w261.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w262
    } else {
      val sec_263 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w264 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_263 < 0)) 0 else (c.now + (sec_263 * 1000))) }) }) }
      val w265 = { ...w264, inc: w264.inc.set(iid, { ...w264.inc.get(iid), timers: w264.inc.get(iid).timers.set("reaction", { ...w264.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w266 = { ...w265, inc: w265.inc.set(iid, { ...w265.inc.get(iid), timers: w265.inc.get(iid).timers.set("reaction", { ...w265.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w267 = { ...w266, inc: w266.inc.set(iid, { ...w266.inc.get(iid), timers: w266.inc.get(iid).timers.set("reaction", { ...w266.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w267
    }
      w259
    }
      w257
    }
    w256
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_268 = c.before.owner
    val w269 = if (((whom_268 != "") and (whom_268 != c.actor))) w0 else w0
    w269
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_270 = addressee(w0.inc.get(iid))
    val w271 = if (((whom_270 != "") and (whom_270 != c.actor))) w0 else w0
    w271
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
    not(settings.session.states.foldl(false, (acc, s_272) => acc or ((s_272.id == agentState(c.me)) and s_272.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_273 = c.actor
    val w274 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_273 }) }
    w274
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_275 = ""
    val w276 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_275 }) }
    w276
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w277 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w277
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w278 = if (timerDef("reaction").startsOnce) {
      val w279 = ec_pauseTimer(w0, c, iid, "reaction")
      w279
    } else {
      val w280 = if (false) {
      val w281 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w282 = { ...w281, inc: w281.inc.set(iid, { ...w281.inc.get(iid), timers: w281.inc.get(iid).timers.set("reaction", { ...w281.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w283 = { ...w282, inc: w282.inc.set(iid, { ...w282.inc.get(iid), timers: w282.inc.get(iid).timers.set("reaction", { ...w282.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w284 = { ...w283, inc: w283.inc.set(iid, { ...w283.inc.get(iid), timers: w283.inc.get(iid).timers.set("reaction", { ...w283.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w284
    } else {
      val w285 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_286 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w287 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_286) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w288 = { ...w287, inc: w287.inc.set(iid, { ...w287.inc.get(iid), timers: w287.inc.get(iid).timers.set("reaction", { ...w287.inc.get(iid).timers.get("reaction"), paused: keep_286 }) }) }
      val w289 = { ...w288, inc: w288.inc.set(iid, { ...w288.inc.get(iid), timers: w288.inc.get(iid).timers.set("reaction", { ...w288.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w290 = { ...w289, inc: w289.inc.set(iid, { ...w289.inc.get(iid), timers: w289.inc.get(iid).timers.set("reaction", { ...w289.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w290
    }
      w285
    }
      w280
    }
    w278
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w291 = if (timerDef("hold").startsOnce) {
      val w292 = ec_pauseTimer(w0, c, iid, "hold")
      w292
    } else {
      val w293 = if (false) {
      val w294 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w295 = { ...w294, inc: w294.inc.set(iid, { ...w294.inc.get(iid), timers: w294.inc.get(iid).timers.set("hold", { ...w294.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w296 = { ...w295, inc: w295.inc.set(iid, { ...w295.inc.get(iid), timers: w295.inc.get(iid).timers.set("hold", { ...w295.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w297 = { ...w296, inc: w296.inc.set(iid, { ...w296.inc.get(iid), timers: w296.inc.get(iid).timers.set("hold", { ...w296.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w297
    } else {
      val w298 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_299 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w300 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_299) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w301 = { ...w300, inc: w300.inc.set(iid, { ...w300.inc.get(iid), timers: w300.inc.get(iid).timers.set("hold", { ...w300.inc.get(iid).timers.get("hold"), paused: keep_299 }) }) }
      val w302 = { ...w301, inc: w301.inc.set(iid, { ...w301.inc.get(iid), timers: w301.inc.get(iid).timers.set("hold", { ...w301.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w303 = { ...w302, inc: w302.inc.set(iid, { ...w302.inc.get(iid), timers: w302.inc.get(iid).timers.set("hold", { ...w302.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w303
    }
      w298
    }
      w293
    }
    w291
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w304 = if (not(timerDef("resolution").pausable)) {
      val sec_305 = timerSec(w0.inc.get(iid), "resolution", "")
      val w306 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_305 < 0)) 0 else (c.now + (sec_305 * 1000))) }) }) }
      val w307 = { ...w306, inc: w306.inc.set(iid, { ...w306.inc.get(iid), timers: w306.inc.get(iid).timers.set("resolution", { ...w306.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w307
    } else {
      val w308 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_309 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w310 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_309 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_309)) }) }) }
      val w311 = { ...w310, inc: w310.inc.set(iid, { ...w310.inc.get(iid), timers: w310.inc.get(iid).timers.set("resolution", { ...w310.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w312 = { ...w311, inc: w311.inc.set(iid, { ...w311.inc.get(iid), timers: w311.inc.get(iid).timers.set("resolution", { ...w311.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w312
    } else w0
      w308
    }
    w304
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
    val whom_313 = c.before.owner
    val w314 = if (((whom_313 != "") and (whom_313 != c.actor))) w0 else w0
    w314
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
    not(settings.session.states.foldl(false, (acc, s_315) => acc or ((s_315.id == agentState(c.me)) and s_315.readOnly))),
    { val os_316 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_316.foldl(false, (acc, o_317) => acc or ((o_317.id == c.form.resultId) and stepsOk(o_317, world.inc.get(iid)))) else os_316.foldl(false, (acc, o_318) => acc or stepsOk(o_318, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_319 = c.actor
    val w320 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_319 }) }
    w320
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_321 = ""
    val w322 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_321 }) }
    w322
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_323 = c.actor
    val w324 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_323 }) }
    w324
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_325 = c.now
    val w326 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_325 }) }
    w326
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_327 = c.form.resultId
    val w328 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_327 }) }
    w328
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_329 = c.form.causeId
    val w330 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_329 }) }
    w330
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_331 = c.form.comment
    val w332 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_331 }) }
    w332
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w333 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w333
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w334 = if (timerDef("reaction").startsOnce) {
      val w335 = ec_pauseTimer(w0, c, iid, "reaction")
      w335
    } else {
      val w336 = if (true) {
      val w337 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w338 = { ...w337, inc: w337.inc.set(iid, { ...w337.inc.get(iid), timers: w337.inc.get(iid).timers.set("reaction", { ...w337.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w339 = { ...w338, inc: w338.inc.set(iid, { ...w338.inc.get(iid), timers: w338.inc.get(iid).timers.set("reaction", { ...w338.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w340 = { ...w339, inc: w339.inc.set(iid, { ...w339.inc.get(iid), timers: w339.inc.get(iid).timers.set("reaction", { ...w339.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w340
    } else {
      val w341 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_342 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w343 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_342) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w344 = { ...w343, inc: w343.inc.set(iid, { ...w343.inc.get(iid), timers: w343.inc.get(iid).timers.set("reaction", { ...w343.inc.get(iid).timers.get("reaction"), paused: keep_342 }) }) }
      val w345 = { ...w344, inc: w344.inc.set(iid, { ...w344.inc.get(iid), timers: w344.inc.get(iid).timers.set("reaction", { ...w344.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w346 = { ...w345, inc: w345.inc.set(iid, { ...w345.inc.get(iid), timers: w345.inc.get(iid).timers.set("reaction", { ...w345.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w346
    }
      w341
    }
      w336
    }
    w334
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w347 = if (not(timerDef("resolution").pausable)) {
      val w348 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w349 = { ...w348, inc: w348.inc.set(iid, { ...w348.inc.get(iid), timers: w348.inc.get(iid).timers.set("resolution", { ...w348.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w349
    } else {
      val w350 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w351 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w352 = { ...w351, inc: w351.inc.set(iid, { ...w351.inc.get(iid), timers: w351.inc.get(iid).timers.set("resolution", { ...w351.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w353 = { ...w352, inc: w352.inc.set(iid, { ...w352.inc.get(iid), timers: w352.inc.get(iid).timers.set("resolution", { ...w352.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w353
    } else w0
      w350
    }
    w347
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w354 = if (timerDef("hold").startsOnce) {
      val w355 = ec_pauseTimer(w0, c, iid, "hold")
      w355
    } else {
      val w356 = if (false) {
      val w357 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w358 = { ...w357, inc: w357.inc.set(iid, { ...w357.inc.get(iid), timers: w357.inc.get(iid).timers.set("hold", { ...w357.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w359 = { ...w358, inc: w358.inc.set(iid, { ...w358.inc.get(iid), timers: w358.inc.get(iid).timers.set("hold", { ...w358.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w360 = { ...w359, inc: w359.inc.set(iid, { ...w359.inc.get(iid), timers: w359.inc.get(iid).timers.set("hold", { ...w359.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w360
    } else {
      val w361 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_362 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w363 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_362) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w364 = { ...w363, inc: w363.inc.set(iid, { ...w363.inc.get(iid), timers: w363.inc.get(iid).timers.set("hold", { ...w363.inc.get(iid).timers.get("hold"), paused: keep_362 }) }) }
      val w365 = { ...w364, inc: w364.inc.set(iid, { ...w364.inc.get(iid), timers: w364.inc.get(iid).timers.set("hold", { ...w364.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w366 = { ...w365, inc: w365.inc.set(iid, { ...w365.inc.get(iid), timers: w365.inc.get(iid).timers.set("hold", { ...w365.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w366
    }
      w361
    }
      w356
    }
    w354
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
    not(settings.session.states.foldl(false, (acc, s_367) => acc or ((s_367.id == agentState(c.me)) and s_367.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_368 = c.actor
    val w369 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_368 }) }
    w369
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w370 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_371 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w372 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w373 = { ...w372, inc: w372.inc.set(iid, { ...w372.inc.get(iid), linkedTo: "" }) }
      val w374 = { ...w373, inc: w373.inc.set(iid, { ...w373.inc.get(iid), linkedAt: 0 }) }
      val w375 = if (((ps_371.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w374 else w374
      val w376 = if (("workflow.journal.linked_reopened" != "")) {
      val w377 = ps_371.foldl([], (acc, x380) => acc.append(x380.id)).foldl(w375, (wf378, pId379) => wf378)
      w377
    } else w375
      w376
    } else {
      val w381 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w382 = { ...w381, inc: w381.inc.set(iid, { ...w381.inc.get(iid), linkedAt: 0 }) }
      w382
    }
    w370
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_383 = ""
    val w384 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_383 }) }
    w384
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_385 = ""
    val w386 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_385 }) }
    w386
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_387 = ""
    val w388 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_387 }) }
    w388
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_389 = 0
    val w390 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_389 }) }
    w390
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_391 = ""
    val w392 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_391 }) }
    w392
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val sec_393 = settings.limits.reopenResolutionSec
    val w394 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_393 > 0)) sec_393 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w395 = { ...w394, inc: w394.inc.set(iid, { ...w394.inc.get(iid), timers: w394.inc.get(iid).timers.set("resolution", { ...w394.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w396 = { ...w395, inc: w395.inc.set(iid, { ...w395.inc.get(iid), timers: w395.inc.get(iid).timers.set("resolution", { ...w395.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w396
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {
    val w397 = if (timerDef("reaction").startsOnce) {
      val w398 = ec_pauseTimer(w0, c, iid, "reaction")
      w398
    } else {
      val w399 = if (true) {
      val w400 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w401 = { ...w400, inc: w400.inc.set(iid, { ...w400.inc.get(iid), timers: w400.inc.get(iid).timers.set("reaction", { ...w400.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w402 = { ...w401, inc: w401.inc.set(iid, { ...w401.inc.get(iid), timers: w401.inc.get(iid).timers.set("reaction", { ...w401.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w403 = { ...w402, inc: w402.inc.set(iid, { ...w402.inc.get(iid), timers: w402.inc.get(iid).timers.set("reaction", { ...w402.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w403
    } else {
      val w404 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_405 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w406 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_405) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w407 = { ...w406, inc: w406.inc.set(iid, { ...w406.inc.get(iid), timers: w406.inc.get(iid).timers.set("reaction", { ...w406.inc.get(iid).timers.get("reaction"), paused: keep_405 }) }) }
      val w408 = { ...w407, inc: w407.inc.set(iid, { ...w407.inc.get(iid), timers: w407.inc.get(iid).timers.set("reaction", { ...w407.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w409 = { ...w408, inc: w408.inc.set(iid, { ...w408.inc.get(iid), timers: w408.inc.get(iid).timers.set("reaction", { ...w408.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w409
    }
      w404
    }
      w399
    }
    w397
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
    { val t_410 = world.inc.get(iid).timers.get("reaction")  (((t_410.due != 0) and (t_410.due <= c.now)) and (t_410.fired != t_410.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_411 = personOf(levelUpTarget(c.before))
    val w412 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_411 }) }
    w412
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_413 = groupOf(levelUpTarget(c.before))
    val w414 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_413 }) }
    w414
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_415 = levelUpNumber(c.before)
    val w416 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_415 }) }
    w416
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w417 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w417
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w418 = if (not(timerDef("resolution").pausable)) {
      val w419 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w420 = { ...w419, inc: w419.inc.set(iid, { ...w419.inc.get(iid), timers: w419.inc.get(iid).timers.set("resolution", { ...w419.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w420
    } else {
      val w421 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w422 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w423 = { ...w422, inc: w422.inc.set(iid, { ...w422.inc.get(iid), timers: w422.inc.get(iid).timers.set("resolution", { ...w422.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w424 = { ...w423, inc: w423.inc.set(iid, { ...w423.inc.get(iid), timers: w423.inc.get(iid).timers.set("resolution", { ...w423.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w424
    } else w0
      w421
    }
    w418
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w425 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w426 = if (timerDef("reaction").startsOnce) {
      val w427 = ec_resumeTimer(w0, c, iid, "reaction")
      w427
    } else {
      val w428 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w429 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w430 = { ...w429, inc: w429.inc.set(iid, { ...w429.inc.get(iid), timers: w429.inc.get(iid).timers.set("reaction", { ...w429.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w431 = { ...w430, inc: w430.inc.set(iid, { ...w430.inc.get(iid), timers: w430.inc.get(iid).timers.set("reaction", { ...w430.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w431
    } else {
      val sec_432 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w433 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_432 < 0)) 0 else (c.now + (sec_432 * 1000))) }) }) }
      val w434 = { ...w433, inc: w433.inc.set(iid, { ...w433.inc.get(iid), timers: w433.inc.get(iid).timers.set("reaction", { ...w433.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w435 = { ...w434, inc: w434.inc.set(iid, { ...w434.inc.get(iid), timers: w434.inc.get(iid).timers.set("reaction", { ...w434.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w436 = { ...w435, inc: w435.inc.set(iid, { ...w435.inc.get(iid), timers: w435.inc.get(iid).timers.set("reaction", { ...w435.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w436
    }
      w428
    }
      w426
    }
    w425
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_437 = addressee(w0.inc.get(iid))
    val w438 = if (((whom_437 != "") and (whom_437 != c.actor))) w0 else w0
    w438
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
    { val t_439 = world.inc.get(iid).timers.get("reaction")  (((t_439.due != 0) and (t_439.due <= c.now)) and (t_439.fired != t_439.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_440 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w441 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_440) }) }
    val w442 = { ...w441, inc: w441.inc.set(iid, { ...w441.inc.get(iid), slaBreached: true }) }
    val w443 = groupMembersAt(incs(w0), w442.inc.get(iid), c.deadline).foldl([], (acc, x446) => acc.append(x446.id)).foldl(w442, (wf444, eId445) => {
      val w447 = { ...wf444, inc: wf444.inc.set(eId445, { ...wf444.inc.get(eId445), breaches: wf444.inc.get(eId445).breaches.append(breach_440) }) }
      val w448 = { ...w447, inc: w447.inc.set(eId445, { ...w447.inc.get(eId445), slaBreached: true }) }
      w448
    })
    w443
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w449 = if (timerDef("reaction").startsOnce) {
      val w450 = ec_pauseTimer(w0, c, iid, "reaction")
      w450
    } else {
      val w451 = if (false) {
      val w452 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w453 = { ...w452, inc: w452.inc.set(iid, { ...w452.inc.get(iid), timers: w452.inc.get(iid).timers.set("reaction", { ...w452.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w454 = { ...w453, inc: w453.inc.set(iid, { ...w453.inc.get(iid), timers: w453.inc.get(iid).timers.set("reaction", { ...w453.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w455 = { ...w454, inc: w454.inc.set(iid, { ...w454.inc.get(iid), timers: w454.inc.get(iid).timers.set("reaction", { ...w454.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w455
    } else {
      val w456 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_457 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w458 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_457) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w459 = { ...w458, inc: w458.inc.set(iid, { ...w458.inc.get(iid), timers: w458.inc.get(iid).timers.set("reaction", { ...w458.inc.get(iid).timers.get("reaction"), paused: keep_457 }) }) }
      val w460 = { ...w459, inc: w459.inc.set(iid, { ...w459.inc.get(iid), timers: w459.inc.get(iid).timers.set("reaction", { ...w459.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w461 = { ...w460, inc: w460.inc.set(iid, { ...w460.inc.get(iid), timers: w460.inc.get(iid).timers.set("reaction", { ...w460.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w461
    }
      w456
    }
      w451
    }
    w449
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_462 = settings.alerts.target
    val w463 = if (((whom_462 != "") and (whom_462 != c.actor))) w0 else w0
    w463
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
    { val t_464 = world.inc.get(iid).timers.get("reaction")  (((t_464.due != 0) and (t_464.due <= c.now)) and (t_464.fired != t_464.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_465 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w466 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_465) }) }
    val w467 = { ...w466, inc: w466.inc.set(iid, { ...w466.inc.get(iid), slaBreached: true }) }
    val w468 = groupMembersAt(incs(w0), w467.inc.get(iid), c.deadline).foldl([], (acc, x471) => acc.append(x471.id)).foldl(w467, (wf469, eId470) => {
      val w472 = { ...wf469, inc: wf469.inc.set(eId470, { ...wf469.inc.get(eId470), breaches: wf469.inc.get(eId470).breaches.append(breach_465) }) }
      val w473 = { ...w472, inc: w472.inc.set(eId470, { ...w472.inc.get(eId470), slaBreached: true }) }
      w473
    })
    w468
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w474 = if (timerDef("reaction").startsOnce) {
      val w475 = ec_pauseTimer(w0, c, iid, "reaction")
      w475
    } else {
      val w476 = if (false) {
      val w477 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w478 = { ...w477, inc: w477.inc.set(iid, { ...w477.inc.get(iid), timers: w477.inc.get(iid).timers.set("reaction", { ...w477.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w479 = { ...w478, inc: w478.inc.set(iid, { ...w478.inc.get(iid), timers: w478.inc.get(iid).timers.set("reaction", { ...w478.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w480 = { ...w479, inc: w479.inc.set(iid, { ...w479.inc.get(iid), timers: w479.inc.get(iid).timers.set("reaction", { ...w479.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w480
    } else {
      val w481 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_482 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w483 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_482) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w484 = { ...w483, inc: w483.inc.set(iid, { ...w483.inc.get(iid), timers: w483.inc.get(iid).timers.set("reaction", { ...w483.inc.get(iid).timers.get("reaction"), paused: keep_482 }) }) }
      val w485 = { ...w484, inc: w484.inc.set(iid, { ...w484.inc.get(iid), timers: w484.inc.get(iid).timers.set("reaction", { ...w484.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w486 = { ...w485, inc: w485.inc.set(iid, { ...w485.inc.get(iid), timers: w485.inc.get(iid).timers.set("reaction", { ...w485.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w486
    }
      w481
    }
      w476
    }
    w474
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_487 = settings.alerts.target
    val w488 = if (((whom_487 != "") and (whom_487 != c.actor))) w0 else w0
    w488
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
    { val t_489 = world.inc.get(iid).timers.get("resolution")  (((t_489.due != 0) and (t_489.due <= c.now)) and (t_489.fired != t_489.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_490 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w491 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_490) }) }
    val w492 = { ...w491, inc: w491.inc.set(iid, { ...w491.inc.get(iid), slaBreached: true }) }
    val w493 = groupMembersAt(incs(w0), w492.inc.get(iid), c.deadline).foldl([], (acc, x496) => acc.append(x496.id)).foldl(w492, (wf494, eId495) => {
      val w497 = { ...wf494, inc: wf494.inc.set(eId495, { ...wf494.inc.get(eId495), breaches: wf494.inc.get(eId495).breaches.append(breach_490) }) }
      val w498 = { ...w497, inc: w497.inc.set(eId495, { ...w497.inc.get(eId495), slaBreached: true }) }
      w498
    })
    w493
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_499 = settings.alerts.target
    val w500 = if (((whom_499 != "") and (whom_499 != c.actor))) w0 else w0
    w500
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
    { val t_501 = world.inc.get(iid).timers.get("resolution")  (((t_501.due != 0) and (t_501.due <= c.now)) and (t_501.fired != t_501.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_502 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w503 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_502) }) }
    val w504 = { ...w503, inc: w503.inc.set(iid, { ...w503.inc.get(iid), slaBreached: true }) }
    val w505 = groupMembersAt(incs(w0), w504.inc.get(iid), c.deadline).foldl([], (acc, x508) => acc.append(x508.id)).foldl(w504, (wf506, eId507) => {
      val w509 = { ...wf506, inc: wf506.inc.set(eId507, { ...wf506.inc.get(eId507), breaches: wf506.inc.get(eId507).breaches.append(breach_502) }) }
      val w510 = { ...w509, inc: w509.inc.set(eId507, { ...w509.inc.get(eId507), slaBreached: true }) }
      w510
    })
    w505
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_511 = personOf(levelUpTarget(c.before))
    val w512 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_511 }) }
    w512
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_513 = groupOf(levelUpTarget(c.before))
    val w514 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_513 }) }
    w514
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_515 = levelUpNumber(c.before)
    val w516 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_515 }) }
    w516
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w517 = if (not(timerDef("resolution").pausable)) {
      val w518 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w519 = { ...w518, inc: w518.inc.set(iid, { ...w518.inc.get(iid), timers: w518.inc.get(iid).timers.set("resolution", { ...w518.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w519
    } else {
      val w520 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w521 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w522 = { ...w521, inc: w521.inc.set(iid, { ...w521.inc.get(iid), timers: w521.inc.get(iid).timers.set("resolution", { ...w521.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w523 = { ...w522, inc: w522.inc.set(iid, { ...w522.inc.get(iid), timers: w522.inc.get(iid).timers.set("resolution", { ...w522.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w523
    } else w0
      w520
    }
    w517
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w524 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w525 = if (timerDef("reaction").startsOnce) {
      val w526 = ec_resumeTimer(w0, c, iid, "reaction")
      w526
    } else {
      val w527 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w528 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w529 = { ...w528, inc: w528.inc.set(iid, { ...w528.inc.get(iid), timers: w528.inc.get(iid).timers.set("reaction", { ...w528.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w530 = { ...w529, inc: w529.inc.set(iid, { ...w529.inc.get(iid), timers: w529.inc.get(iid).timers.set("reaction", { ...w529.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w530
    } else {
      val sec_531 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w532 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_531 < 0)) 0 else (c.now + (sec_531 * 1000))) }) }) }
      val w533 = { ...w532, inc: w532.inc.set(iid, { ...w532.inc.get(iid), timers: w532.inc.get(iid).timers.set("reaction", { ...w532.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w534 = { ...w533, inc: w533.inc.set(iid, { ...w533.inc.get(iid), timers: w533.inc.get(iid).timers.set("reaction", { ...w533.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w535 = { ...w534, inc: w534.inc.set(iid, { ...w534.inc.get(iid), timers: w534.inc.get(iid).timers.set("reaction", { ...w534.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w535
    }
      w527
    }
      w525
    }
    w524
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_536 = c.before.owner
    val w537 = if (((whom_536 != "") and (whom_536 != c.actor))) w0 else w0
    w537
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_538 = addressee(w0.inc.get(iid))
    val w539 = if (((whom_538 != "") and (whom_538 != c.actor))) w0 else w0
    w539
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
    { val t_540 = world.inc.get(iid).timers.get("resolution")  (((t_540.due != 0) and (t_540.due <= c.now)) and (t_540.fired != t_540.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_541 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w542 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_541) }) }
    val w543 = { ...w542, inc: w542.inc.set(iid, { ...w542.inc.get(iid), slaBreached: true }) }
    val w544 = groupMembersAt(incs(w0), w543.inc.get(iid), c.deadline).foldl([], (acc, x547) => acc.append(x547.id)).foldl(w543, (wf545, eId546) => {
      val w548 = { ...wf545, inc: wf545.inc.set(eId546, { ...wf545.inc.get(eId546), breaches: wf545.inc.get(eId546).breaches.append(breach_541) }) }
      val w549 = { ...w548, inc: w548.inc.set(eId546, { ...w548.inc.get(eId546), slaBreached: true }) }
      w549
    })
    w544
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_550 = settings.alerts.target
    val w551 = if (((whom_550 != "") and (whom_550 != c.actor))) w0 else w0
    w551
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
    { val t_552 = world.inc.get(iid).timers.get("hold")  (((t_552.due != 0) and (t_552.due <= c.now)) and (t_552.fired != t_552.due)) },
    not(["break", "no_link"].foldl(false, (acc, y553) => acc or y553 == world.inc.get(iid).holdReasonId)),
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_554 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w555 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_554) }) }
    val w556 = { ...w555, inc: w555.inc.set(iid, { ...w555.inc.get(iid), slaBreached: true }) }
    val w557 = groupMembersAt(incs(w0), w556.inc.get(iid), c.deadline).foldl([], (acc, x560) => acc.append(x560.id)).foldl(w556, (wf558, eId559) => {
      val w561 = { ...wf558, inc: wf558.inc.set(eId559, { ...wf558.inc.get(eId559), breaches: wf558.inc.get(eId559).breaches.append(breach_554) }) }
      val w562 = { ...w561, inc: w561.inc.set(eId559, { ...w561.inc.get(eId559), slaBreached: true }) }
      w562
    })
    w557
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_563 = settings.alerts.target
    val w564 = if (((whom_563 != "") and (whom_563 != c.actor))) w0 else w0
    w564
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
    { val t_565 = world.inc.get(iid).timers.get("hold")  (((t_565.due != 0) and (t_565.due <= c.now)) and (t_565.fired != t_565.due)) },
    ["break"].foldl(false, (acc, y566) => acc or y566 == world.inc.get(iid).holdReasonId),
  }

  def e_break_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_567 = ""
    val w568 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_567 }) }
    w568
  }

  def e_break_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w569 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w569
  }

  def e_break_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w570 = if (timerDef("hold").startsOnce) {
      val w571 = ec_pauseTimer(w0, c, iid, "hold")
      w571
    } else {
      val w572 = if (false) {
      val w573 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w574 = { ...w573, inc: w573.inc.set(iid, { ...w573.inc.get(iid), timers: w573.inc.get(iid).timers.set("hold", { ...w573.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w575 = { ...w574, inc: w574.inc.set(iid, { ...w574.inc.get(iid), timers: w574.inc.get(iid).timers.set("hold", { ...w574.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w576 = { ...w575, inc: w575.inc.set(iid, { ...w575.inc.get(iid), timers: w575.inc.get(iid).timers.set("hold", { ...w575.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w576
    } else {
      val w577 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_578 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w579 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_578) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w580 = { ...w579, inc: w579.inc.set(iid, { ...w579.inc.get(iid), timers: w579.inc.get(iid).timers.set("hold", { ...w579.inc.get(iid).timers.get("hold"), paused: keep_578 }) }) }
      val w581 = { ...w580, inc: w580.inc.set(iid, { ...w580.inc.get(iid), timers: w580.inc.get(iid).timers.set("hold", { ...w580.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w582 = { ...w581, inc: w581.inc.set(iid, { ...w581.inc.get(iid), timers: w581.inc.get(iid).timers.set("hold", { ...w581.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w582
    }
      w577
    }
      w572
    }
    w570
  }

  def e_break_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w583 = if (not(timerDef("resolution").pausable)) {
      val w584 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w585 = { ...w584, inc: w584.inc.set(iid, { ...w584.inc.get(iid), timers: w584.inc.get(iid).timers.set("resolution", { ...w584.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w585
    } else {
      val w586 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w587 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w588 = { ...w587, inc: w587.inc.set(iid, { ...w587.inc.get(iid), timers: w587.inc.get(iid).timers.set("resolution", { ...w587.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w589 = { ...w588, inc: w588.inc.set(iid, { ...w588.inc.get(iid), timers: w588.inc.get(iid).timers.set("resolution", { ...w588.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w589
    } else w0
      w586
    }
    w583
  }

  def e_break_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w590 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w591 = if (timerDef("reaction").startsOnce) {
      val w592 = ec_resumeTimer(w0, c, iid, "reaction")
      w592
    } else {
      val w593 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w594 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w595 = { ...w594, inc: w594.inc.set(iid, { ...w594.inc.get(iid), timers: w594.inc.get(iid).timers.set("reaction", { ...w594.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w596 = { ...w595, inc: w595.inc.set(iid, { ...w595.inc.get(iid), timers: w595.inc.get(iid).timers.set("reaction", { ...w595.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w596
    } else {
      val sec_597 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w598 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_597 < 0)) 0 else (c.now + (sec_597 * 1000))) }) }) }
      val w599 = { ...w598, inc: w598.inc.set(iid, { ...w598.inc.get(iid), timers: w598.inc.get(iid).timers.set("reaction", { ...w598.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w600 = { ...w599, inc: w599.inc.set(iid, { ...w599.inc.get(iid), timers: w599.inc.get(iid).timers.set("reaction", { ...w599.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w601 = { ...w600, inc: w600.inc.set(iid, { ...w600.inc.get(iid), timers: w600.inc.get(iid).timers.set("reaction", { ...w600.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w601
    }
      w593
    }
      w591
    }
    w590
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
    val reason_602 = "break"
    val w603 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_602 }) }
    w603
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w604 = if (not(timerDef("resolution").pausable)) {
      val w605 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w606 = { ...w605, inc: w605.inc.set(iid, { ...w605.inc.get(iid), timers: w605.inc.get(iid).timers.set("resolution", { ...w605.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w606
    } else {
      val w607 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w608 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w609 = { ...w608, inc: w608.inc.set(iid, { ...w608.inc.get(iid), timers: w608.inc.get(iid).timers.set("resolution", { ...w608.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w610 = { ...w609, inc: w609.inc.set(iid, { ...w609.inc.get(iid), timers: w609.inc.get(iid).timers.set("resolution", { ...w609.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w610
    } else w0
      w607
    }
    w604
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w611 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w612 = if (timerDef("hold").startsOnce) {
      val w613 = ec_resumeTimer(w0, c, iid, "hold")
      w613
    } else {
      val w614 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w615 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w616 = { ...w615, inc: w615.inc.set(iid, { ...w615.inc.get(iid), timers: w615.inc.get(iid).timers.set("hold", { ...w615.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w617 = { ...w616, inc: w616.inc.set(iid, { ...w616.inc.get(iid), timers: w616.inc.get(iid).timers.set("hold", { ...w616.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w617
    } else {
      val sec_618 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w619 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_618 < 0)) 0 else (c.now + (sec_618 * 1000))) }) }) }
      val w620 = { ...w619, inc: w619.inc.set(iid, { ...w619.inc.get(iid), timers: w619.inc.get(iid).timers.set("hold", { ...w619.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w621 = { ...w620, inc: w620.inc.set(iid, { ...w620.inc.get(iid), timers: w620.inc.get(iid).timers.set("hold", { ...w620.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w622 = { ...w621, inc: w621.inc.set(iid, { ...w621.inc.get(iid), timers: w621.inc.get(iid).timers.set("hold", { ...w621.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w622
    }
      w614
    }
      w612
    }
    w611
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
    val reason_623 = "no_link"
    val w624 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_623 }) }
    w624
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w625 = if (not(timerDef("resolution").pausable)) {
      val w626 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w627 = { ...w626, inc: w626.inc.set(iid, { ...w626.inc.get(iid), timers: w626.inc.get(iid).timers.set("resolution", { ...w626.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w627
    } else {
      val w628 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w629 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w630 = { ...w629, inc: w629.inc.set(iid, { ...w629.inc.get(iid), timers: w629.inc.get(iid).timers.set("resolution", { ...w629.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w631 = { ...w630, inc: w630.inc.set(iid, { ...w630.inc.get(iid), timers: w630.inc.get(iid).timers.set("resolution", { ...w630.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w631
    } else w0
      w628
    }
    w625
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w632 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w633 = if (timerDef("hold").startsOnce) {
      val w634 = ec_resumeTimer(w0, c, iid, "hold")
      w634
    } else {
      val w635 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w636 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w637 = { ...w636, inc: w636.inc.set(iid, { ...w636.inc.get(iid), timers: w636.inc.get(iid).timers.set("hold", { ...w636.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w638 = { ...w637, inc: w637.inc.set(iid, { ...w637.inc.get(iid), timers: w637.inc.get(iid).timers.set("hold", { ...w637.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w638
    } else {
      val sec_639 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w640 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_639 < 0)) 0 else (c.now + (sec_639 * 1000))) }) }) }
      val w641 = { ...w640, inc: w640.inc.set(iid, { ...w640.inc.get(iid), timers: w640.inc.get(iid).timers.set("hold", { ...w640.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w642 = { ...w641, inc: w641.inc.set(iid, { ...w641.inc.get(iid), timers: w641.inc.get(iid).timers.set("hold", { ...w641.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w643 = { ...w642, inc: w642.inc.set(iid, { ...w642.inc.get(iid), timers: w642.inc.get(iid).timers.set("hold", { ...w642.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w643
    }
      w635
    }
      w633
    }
    w632
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_644 = settings.alerts.target
    val w645 = if (((whom_644 != "") and (whom_644 != c.actor))) w0 else w0
    w645
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
    ["break", "no_link"].foldl(false, (acc, y646) => acc or y646 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_647 = ""
    val w648 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_647 }) }
    w648
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w649 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w649
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w650 = if (timerDef("hold").startsOnce) {
      val w651 = ec_pauseTimer(w0, c, iid, "hold")
      w651
    } else {
      val w652 = if (false) {
      val w653 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w654 = { ...w653, inc: w653.inc.set(iid, { ...w653.inc.get(iid), timers: w653.inc.get(iid).timers.set("hold", { ...w653.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w655 = { ...w654, inc: w654.inc.set(iid, { ...w654.inc.get(iid), timers: w654.inc.get(iid).timers.set("hold", { ...w654.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w656 = { ...w655, inc: w655.inc.set(iid, { ...w655.inc.get(iid), timers: w655.inc.get(iid).timers.set("hold", { ...w655.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w656
    } else {
      val w657 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_658 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w659 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_658) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w660 = { ...w659, inc: w659.inc.set(iid, { ...w659.inc.get(iid), timers: w659.inc.get(iid).timers.set("hold", { ...w659.inc.get(iid).timers.get("hold"), paused: keep_658 }) }) }
      val w661 = { ...w660, inc: w660.inc.set(iid, { ...w660.inc.get(iid), timers: w660.inc.get(iid).timers.set("hold", { ...w660.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w662 = { ...w661, inc: w661.inc.set(iid, { ...w661.inc.get(iid), timers: w661.inc.get(iid).timers.set("hold", { ...w661.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w662
    }
      w657
    }
      w652
    }
    w650
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w663 = if (not(timerDef("resolution").pausable)) {
      val w664 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w665 = { ...w664, inc: w664.inc.set(iid, { ...w664.inc.get(iid), timers: w664.inc.get(iid).timers.set("resolution", { ...w664.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w665
    } else {
      val w666 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w667 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w668 = { ...w667, inc: w667.inc.set(iid, { ...w667.inc.get(iid), timers: w667.inc.get(iid).timers.set("resolution", { ...w667.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w669 = { ...w668, inc: w668.inc.set(iid, { ...w668.inc.get(iid), timers: w668.inc.get(iid).timers.set("resolution", { ...w668.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w669
    } else w0
      w666
    }
    w663
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w670 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w671 = if (timerDef("reaction").startsOnce) {
      val w672 = ec_resumeTimer(w0, c, iid, "reaction")
      w672
    } else {
      val w673 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w674 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w675 = { ...w674, inc: w674.inc.set(iid, { ...w674.inc.get(iid), timers: w674.inc.get(iid).timers.set("reaction", { ...w674.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w676 = { ...w675, inc: w675.inc.set(iid, { ...w675.inc.get(iid), timers: w675.inc.get(iid).timers.set("reaction", { ...w675.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w676
    } else {
      val sec_677 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w678 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_677 < 0)) 0 else (c.now + (sec_677 * 1000))) }) }) }
      val w679 = { ...w678, inc: w678.inc.set(iid, { ...w678.inc.get(iid), timers: w678.inc.get(iid).timers.set("reaction", { ...w678.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w680 = { ...w679, inc: w679.inc.set(iid, { ...w679.inc.get(iid), timers: w679.inc.get(iid).timers.set("reaction", { ...w679.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w681 = { ...w680, inc: w680.inc.set(iid, { ...w680.inc.get(iid), timers: w680.inc.get(iid).timers.set("reaction", { ...w680.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w681
    }
      w673
    }
      w671
    }
    w670
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
    { val t_682 = world.inc.get(iid).timers.get("hold")  (((t_682.due != 0) and (t_682.due <= c.now)) and (t_682.fired != t_682.due)) },
    ["no_link"].foldl(false, (acc, y683) => acc or y683 == world.inc.get(iid).holdReasonId),
  }

  def e_no_link_hold_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_684 = ""
    val w685 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_684 }) }
    w685
  }

  def e_no_link_hold_release_1(w0: World, c: Ctx, iid: str): World = {
    val w686 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w686
  }

  def e_no_link_hold_release_2(w0: World, c: Ctx, iid: str): World = {
    val w687 = if (timerDef("hold").startsOnce) {
      val w688 = ec_pauseTimer(w0, c, iid, "hold")
      w688
    } else {
      val w689 = if (false) {
      val w690 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w691 = { ...w690, inc: w690.inc.set(iid, { ...w690.inc.get(iid), timers: w690.inc.get(iid).timers.set("hold", { ...w690.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w692 = { ...w691, inc: w691.inc.set(iid, { ...w691.inc.get(iid), timers: w691.inc.get(iid).timers.set("hold", { ...w691.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w693 = { ...w692, inc: w692.inc.set(iid, { ...w692.inc.get(iid), timers: w692.inc.get(iid).timers.set("hold", { ...w692.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w693
    } else {
      val w694 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_695 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w696 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_695) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w697 = { ...w696, inc: w696.inc.set(iid, { ...w696.inc.get(iid), timers: w696.inc.get(iid).timers.set("hold", { ...w696.inc.get(iid).timers.get("hold"), paused: keep_695 }) }) }
      val w698 = { ...w697, inc: w697.inc.set(iid, { ...w697.inc.get(iid), timers: w697.inc.get(iid).timers.set("hold", { ...w697.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w699 = { ...w698, inc: w698.inc.set(iid, { ...w698.inc.get(iid), timers: w698.inc.get(iid).timers.set("hold", { ...w698.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w699
    }
      w694
    }
      w689
    }
    w687
  }

  def e_no_link_hold_release_3(w0: World, c: Ctx, iid: str): World = {
    val w700 = if (not(timerDef("resolution").pausable)) {
      val w701 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w702 = { ...w701, inc: w701.inc.set(iid, { ...w701.inc.get(iid), timers: w701.inc.get(iid).timers.set("resolution", { ...w701.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w702
    } else {
      val w703 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w704 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w705 = { ...w704, inc: w704.inc.set(iid, { ...w704.inc.get(iid), timers: w704.inc.get(iid).timers.set("resolution", { ...w704.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w706 = { ...w705, inc: w705.inc.set(iid, { ...w705.inc.get(iid), timers: w705.inc.get(iid).timers.set("resolution", { ...w705.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w706
    } else w0
      w703
    }
    w700
  }

  def e_no_link_hold_release_4(w0: World, c: Ctx, iid: str): World = {
    val w707 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w708 = if (timerDef("reaction").startsOnce) {
      val w709 = ec_resumeTimer(w0, c, iid, "reaction")
      w709
    } else {
      val w710 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w711 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w712 = { ...w711, inc: w711.inc.set(iid, { ...w711.inc.get(iid), timers: w711.inc.get(iid).timers.set("reaction", { ...w711.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w713 = { ...w712, inc: w712.inc.set(iid, { ...w712.inc.get(iid), timers: w712.inc.get(iid).timers.set("reaction", { ...w712.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w713
    } else {
      val sec_714 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w715 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_714 < 0)) 0 else (c.now + (sec_714 * 1000))) }) }) }
      val w716 = { ...w715, inc: w715.inc.set(iid, { ...w715.inc.get(iid), timers: w715.inc.get(iid).timers.set("reaction", { ...w715.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w717 = { ...w716, inc: w716.inc.set(iid, { ...w716.inc.get(iid), timers: w716.inc.get(iid).timers.set("reaction", { ...w716.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w718 = { ...w717, inc: w717.inc.set(iid, { ...w717.inc.get(iid), timers: w717.inc.get(iid).timers.set("reaction", { ...w717.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w718
    }
      w710
    }
      w708
    }
    w707
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
    val group_719 = dutyGroupOf(w0.inc.get(iid).owner)
    val w720 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_719 }) }
    w720
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_721 = ""
    val w722 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_721 }) }
    w722
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_723 = addressee(w0.inc.get(iid))
    val w724 = if (((whom_723 != "") and (whom_723 != c.actor))) w0 else w0
    w724
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
    val who_725 = ""
    val w726 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_725 }) }
    w726
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
    val who_727 = ""
    val w728 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_727 }) }
    w728
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w729 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w729
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w730 = if (timerDef("hold").startsOnce) {
      val w731 = ec_pauseTimer(w0, c, iid, "hold")
      w731
    } else {
      val w732 = if (false) {
      val w733 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w734 = { ...w733, inc: w733.inc.set(iid, { ...w733.inc.get(iid), timers: w733.inc.get(iid).timers.set("hold", { ...w733.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w735 = { ...w734, inc: w734.inc.set(iid, { ...w734.inc.get(iid), timers: w734.inc.get(iid).timers.set("hold", { ...w734.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w736 = { ...w735, inc: w735.inc.set(iid, { ...w735.inc.get(iid), timers: w735.inc.get(iid).timers.set("hold", { ...w735.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w736
    } else {
      val w737 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_738 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w739 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_738) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w740 = { ...w739, inc: w739.inc.set(iid, { ...w739.inc.get(iid), timers: w739.inc.get(iid).timers.set("hold", { ...w739.inc.get(iid).timers.get("hold"), paused: keep_738 }) }) }
      val w741 = { ...w740, inc: w740.inc.set(iid, { ...w740.inc.get(iid), timers: w740.inc.get(iid).timers.set("hold", { ...w740.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w742 = { ...w741, inc: w741.inc.set(iid, { ...w741.inc.get(iid), timers: w741.inc.get(iid).timers.set("hold", { ...w741.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w742
    }
      w737
    }
      w732
    }
    w730
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w743 = if (not(timerDef("resolution").pausable)) {
      val w744 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w745 = { ...w744, inc: w744.inc.set(iid, { ...w744.inc.get(iid), timers: w744.inc.get(iid).timers.set("resolution", { ...w744.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w745
    } else {
      val w746 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w747 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w748 = { ...w747, inc: w747.inc.set(iid, { ...w747.inc.get(iid), timers: w747.inc.get(iid).timers.set("resolution", { ...w747.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w749 = { ...w748, inc: w748.inc.set(iid, { ...w748.inc.get(iid), timers: w748.inc.get(iid).timers.set("resolution", { ...w748.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w749
    } else w0
      w746
    }
    w743
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w750 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w751 = if (timerDef("reaction").startsOnce) {
      val w752 = ec_resumeTimer(w0, c, iid, "reaction")
      w752
    } else {
      val w753 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w754 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w755 = { ...w754, inc: w754.inc.set(iid, { ...w754.inc.get(iid), timers: w754.inc.get(iid).timers.set("reaction", { ...w754.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w756 = { ...w755, inc: w755.inc.set(iid, { ...w755.inc.get(iid), timers: w755.inc.get(iid).timers.set("reaction", { ...w755.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w756
    } else {
      val sec_757 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w758 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_757 < 0)) 0 else (c.now + (sec_757 * 1000))) }) }) }
      val w759 = { ...w758, inc: w758.inc.set(iid, { ...w758.inc.get(iid), timers: w758.inc.get(iid).timers.set("reaction", { ...w758.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w760 = { ...w759, inc: w759.inc.set(iid, { ...w759.inc.get(iid), timers: w759.inc.get(iid).timers.set("reaction", { ...w759.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w761 = { ...w760, inc: w760.inc.set(iid, { ...w760.inc.get(iid), timers: w760.inc.get(iid).timers.set("reaction", { ...w760.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w761
    }
      w753
    }
      w751
    }
    w750
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
    val who_762 = ""
    val w763 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_762 }) }
    w763
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_764 = ""
    val w765 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_764 }) }
    w765
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w766 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w766
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w767 = if (timerDef("hold").startsOnce) {
      val w768 = ec_pauseTimer(w0, c, iid, "hold")
      w768
    } else {
      val w769 = if (false) {
      val w770 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w771 = { ...w770, inc: w770.inc.set(iid, { ...w770.inc.get(iid), timers: w770.inc.get(iid).timers.set("hold", { ...w770.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w772 = { ...w771, inc: w771.inc.set(iid, { ...w771.inc.get(iid), timers: w771.inc.get(iid).timers.set("hold", { ...w771.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w773 = { ...w772, inc: w772.inc.set(iid, { ...w772.inc.get(iid), timers: w772.inc.get(iid).timers.set("hold", { ...w772.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w773
    } else {
      val w774 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_775 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w776 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_775) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w777 = { ...w776, inc: w776.inc.set(iid, { ...w776.inc.get(iid), timers: w776.inc.get(iid).timers.set("hold", { ...w776.inc.get(iid).timers.get("hold"), paused: keep_775 }) }) }
      val w778 = { ...w777, inc: w777.inc.set(iid, { ...w777.inc.get(iid), timers: w777.inc.get(iid).timers.set("hold", { ...w777.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w779 = { ...w778, inc: w778.inc.set(iid, { ...w778.inc.get(iid), timers: w778.inc.get(iid).timers.set("hold", { ...w778.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w779
    }
      w774
    }
      w769
    }
    w767
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w780 = if (not(timerDef("resolution").pausable)) {
      val w781 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w782 = { ...w781, inc: w781.inc.set(iid, { ...w781.inc.get(iid), timers: w781.inc.get(iid).timers.set("resolution", { ...w781.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w782
    } else {
      val w783 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w784 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w785 = { ...w784, inc: w784.inc.set(iid, { ...w784.inc.get(iid), timers: w784.inc.get(iid).timers.set("resolution", { ...w784.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w786 = { ...w785, inc: w785.inc.set(iid, { ...w785.inc.get(iid), timers: w785.inc.get(iid).timers.set("resolution", { ...w785.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w786
    } else w0
      w783
    }
    w780
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w787 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w788 = if (timerDef("reaction").startsOnce) {
      val w789 = ec_resumeTimer(w0, c, iid, "reaction")
      w789
    } else {
      val w790 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w791 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w792 = { ...w791, inc: w791.inc.set(iid, { ...w791.inc.get(iid), timers: w791.inc.get(iid).timers.set("reaction", { ...w791.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w793 = { ...w792, inc: w792.inc.set(iid, { ...w792.inc.get(iid), timers: w792.inc.get(iid).timers.set("reaction", { ...w792.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w793
    } else {
      val sec_794 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w795 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_794 < 0)) 0 else (c.now + (sec_794 * 1000))) }) }) }
      val w796 = { ...w795, inc: w795.inc.set(iid, { ...w795.inc.get(iid), timers: w795.inc.get(iid).timers.set("reaction", { ...w795.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w797 = { ...w796, inc: w796.inc.set(iid, { ...w796.inc.get(iid), timers: w796.inc.get(iid).timers.set("reaction", { ...w796.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w798 = { ...w797, inc: w797.inc.set(iid, { ...w797.inc.get(iid), timers: w797.inc.get(iid).timers.set("reaction", { ...w797.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w798
    }
      w790
    }
      w788
    }
    w787
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_799 = settings.alerts.target
    val w800 = if (((whom_799 != "") and (whom_799 != c.actor))) w0 else w0
    w800
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
    val who_801 = ""
    val w802 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_801 }) }
    w802
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_803 = ""
    val w804 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_803 }) }
    w804
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w805 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w806 = if (timerDef("reaction").startsOnce) {
      val w807 = ec_resumeTimer(w0, c, iid, "reaction")
      w807
    } else {
      val w808 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w809 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w810 = { ...w809, inc: w809.inc.set(iid, { ...w809.inc.get(iid), timers: w809.inc.get(iid).timers.set("reaction", { ...w809.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w811 = { ...w810, inc: w810.inc.set(iid, { ...w810.inc.get(iid), timers: w810.inc.get(iid).timers.set("reaction", { ...w810.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w811
    } else {
      val sec_812 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w813 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_812 < 0)) 0 else (c.now + (sec_812 * 1000))) }) }) }
      val w814 = { ...w813, inc: w813.inc.set(iid, { ...w813.inc.get(iid), timers: w813.inc.get(iid).timers.set("reaction", { ...w813.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w815 = { ...w814, inc: w814.inc.set(iid, { ...w814.inc.get(iid), timers: w814.inc.get(iid).timers.set("reaction", { ...w814.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w816 = { ...w815, inc: w815.inc.set(iid, { ...w815.inc.get(iid), timers: w815.inc.get(iid).timers.set("reaction", { ...w815.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w816
    }
      w808
    }
      w806
    }
    w805
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_817 = settings.alerts.target
    val w818 = if (((whom_817 != "") and (whom_817 != c.actor))) w0 else w0
    w818
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
    not(settings.session.states.foldl(false, (acc, s_819) => acc or ((s_819.id == agentState(c.me)) and s_819.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_820 = incidentById(incs(world), c.form.primaryId)  ((((ps_820.length() > 0) and (ps_820[0].id != world.inc.get(iid).id)) and (ps_820[0].linkedTo == "")) and ((ps_820[0].state == "new") or ((ps_820[0].state == "in_progress") and (ps_820[0].owner == c.me)))) },
    { val ps_821 = incidentById(incs(world), c.form.primaryId)  ((ps_821.length() > 0) and (ps_821[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w822 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w822
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_823 = incidentById(incs(w0), c.form.primaryId)
    val w824 = if ((ps_823.length() > 0)) {
      val w825 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_832 => not(isDone(e_832))).foldl([], (acc, x828) => acc.append(x828.id)).foldl(w0, (wf826, cId827) => {
      val w829 = { ...wf826, inc: wf826.inc.set(cId827, { ...wf826.inc.get(cId827), leftGroup: { primaryId: wf826.inc.get(cId827).linkedTo, linkedAt: wf826.inc.get(cId827).linkedAt, at: c.now } }) }
      val w830 = { ...w829, inc: w829.inc.set(cId827, { ...w829.inc.get(cId827), linkedTo: ps_823[0].id }) }
      val w831 = { ...w830, inc: w830.inc.set(cId827, { ...w830.inc.get(cId827), linkedAt: c.now }) }
      w831
    })
      w825
    } else w0
    w824
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_833 = c.form.primaryId
    val w834 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_833 }) }
    val w835 = { ...w834, inc: w834.inc.set(iid, { ...w834.inc.get(iid), linkedAt: c.now }) }
    w835
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_836 = ""
    val w837 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_836 }) }
    w837
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_838 = ""
    val w839 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_838 }) }
    w839
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w840 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w840
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w841 = if (timerDef("reaction").startsOnce) {
      val w842 = ec_pauseTimer(w0, c, iid, "reaction")
      w842
    } else {
      val w843 = if (false) {
      val w844 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      val w845 = { ...w844, inc: w844.inc.set(iid, { ...w844.inc.get(iid), timers: w844.inc.get(iid).timers.set("reaction", { ...w844.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w846 = { ...w845, inc: w845.inc.set(iid, { ...w845.inc.get(iid), timers: w845.inc.get(iid).timers.set("reaction", { ...w845.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w847 = { ...w846, inc: w846.inc.set(iid, { ...w846.inc.get(iid), timers: w846.inc.get(iid).timers.set("reaction", { ...w846.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w847
    } else {
      val w848 = if ((w0.inc.get(iid).timers.get("reaction").due == 0)) w0 else {
      val keep_849 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w850 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_849) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w851 = { ...w850, inc: w850.inc.set(iid, { ...w850.inc.get(iid), timers: w850.inc.get(iid).timers.set("reaction", { ...w850.inc.get(iid).timers.get("reaction"), paused: keep_849 }) }) }
      val w852 = { ...w851, inc: w851.inc.set(iid, { ...w851.inc.get(iid), timers: w851.inc.get(iid).timers.set("reaction", { ...w851.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w853 = { ...w852, inc: w852.inc.set(iid, { ...w852.inc.get(iid), timers: w852.inc.get(iid).timers.set("reaction", { ...w852.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w853
    }
      w848
    }
      w843
    }
    w841
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w854 = if (not(timerDef("resolution").pausable)) {
      val w855 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w856 = { ...w855, inc: w855.inc.set(iid, { ...w855.inc.get(iid), timers: w855.inc.get(iid).timers.set("resolution", { ...w855.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w856
    } else {
      val w857 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w858 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w859 = { ...w858, inc: w858.inc.set(iid, { ...w858.inc.get(iid), timers: w858.inc.get(iid).timers.set("resolution", { ...w858.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w860 = { ...w859, inc: w859.inc.set(iid, { ...w859.inc.get(iid), timers: w859.inc.get(iid).timers.set("resolution", { ...w859.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w860
    } else w0
      w857
    }
    w854
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_861 = incidentById(incs(w0), c.form.primaryId)
    val w862 = if (((((ps_861.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_861[0], "resolution", c.now)))) {
      val t_863 = ps_861[0].timers.get("resolution")
      val left_864 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_865 = (if ((t_863.due != 0)) (t_863.due - c.now) else (if (t_863.paused) t_863.left else (timerSec(ps_861[0], "resolution", "") * 1000)))
      val w866 = if ((left_864 < was_865)) {
      val w867 = ps_861.foldl([], (acc, x870) => acc.append(x870.id)).foldl(w0, (wf868, pId869) => {
      val w871 = if ((t_863.due != 0)) {
      val w872 = { ...wf868, inc: wf868.inc.set(pId869, { ...wf868.inc.get(pId869), timers: wf868.inc.get(pId869).timers.set("resolution", { ...wf868.inc.get(pId869).timers.get("resolution"), due: (c.now + left_864) }) }) }
      w872
    } else {
      val w873 = { ...wf868, inc: wf868.inc.set(pId869, { ...wf868.inc.get(pId869), timers: wf868.inc.get(pId869).timers.set("resolution", { ...wf868.inc.get(pId869).timers.get("resolution"), left: left_864 }) }) }
      val w874 = { ...w873, inc: w873.inc.set(pId869, { ...w873.inc.get(pId869), timers: w873.inc.get(pId869).timers.set("resolution", { ...w873.inc.get(pId869).timers.get("resolution"), paused: true }) }) }
      w874
    }
      w871
    })
      w867
    } else w0
      w866
    } else w0
    w862
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w875 = if (timerDef("hold").startsOnce) {
      val w876 = ec_pauseTimer(w0, c, iid, "hold")
      w876
    } else {
      val w877 = if (false) {
      val w878 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      val w879 = { ...w878, inc: w878.inc.set(iid, { ...w878.inc.get(iid), timers: w878.inc.get(iid).timers.set("hold", { ...w878.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w880 = { ...w879, inc: w879.inc.set(iid, { ...w879.inc.get(iid), timers: w879.inc.get(iid).timers.set("hold", { ...w879.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w881 = { ...w880, inc: w880.inc.set(iid, { ...w880.inc.get(iid), timers: w880.inc.get(iid).timers.set("hold", { ...w880.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w881
    } else {
      val w882 = if ((w0.inc.get(iid).timers.get("hold").due == 0)) w0 else {
      val keep_883 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w884 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_883) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w885 = { ...w884, inc: w884.inc.set(iid, { ...w884.inc.get(iid), timers: w884.inc.get(iid).timers.set("hold", { ...w884.inc.get(iid).timers.get("hold"), paused: keep_883 }) }) }
      val w886 = { ...w885, inc: w885.inc.set(iid, { ...w885.inc.get(iid), timers: w885.inc.get(iid).timers.set("hold", { ...w885.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w887 = { ...w886, inc: w886.inc.set(iid, { ...w886.inc.get(iid), timers: w886.inc.get(iid).timers.set("hold", { ...w886.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w887
    }
      w882
    }
      w877
    }
    w875
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
    not(settings.session.states.foldl(false, (acc, s_888) => acc or ((s_888.id == agentState(c.me)) and s_888.readOnly))),
    { val ps_889 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_889.length() > 0) and ((ownership(c.me, ps_889[0]) == "owner") or unowned(ps_889[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_890 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w891 = if (((ps_890.length() > 0) and (leftOf(ps_890[0], "resolution", c.now) >= 0))) {
      val w892 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w893 = { ...w892, inc: w892.inc.set(iid, { ...w892.inc.get(iid), timers: w892.inc.get(iid).timers.set("resolution", { ...w892.inc.get(iid).timers.get("resolution"), left: leftOf(ps_890[0], "resolution", c.now) }) }) }
      val w894 = { ...w893, inc: w893.inc.set(iid, { ...w893.inc.get(iid), timers: w893.inc.get(iid).timers.set("resolution", { ...w893.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w895 = if ((leftOf(ps_890[0], "resolution", c.now) == 0)) {
      val w896 = { ...w894, inc: w894.inc.set(iid, { ...w894.inc.get(iid), timers: w894.inc.get(iid).timers.set("resolution", { ...w894.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_890[0], "resolution", c.now)) ps_890[0].timers.get("resolution").fired else ps_890[0].timers.get("resolution").due) }) }) }
      w896
    } else w894
      w895
    } else w0
    w891
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w897 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_898 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w899 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w900 = { ...w899, inc: w899.inc.set(iid, { ...w899.inc.get(iid), linkedTo: "" }) }
      val w901 = { ...w900, inc: w900.inc.set(iid, { ...w900.inc.get(iid), linkedAt: 0 }) }
      val w902 = if (((ps_898.length() > 0) and ("" != ""))) w901 else w901
      val w903 = if (("" != "")) {
      val w904 = ps_898.foldl([], (acc, x907) => acc.append(x907.id)).foldl(w902, (wf905, pId906) => wf905)
      w904
    } else w902
      w903
    } else {
      val w908 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w909 = { ...w908, inc: w908.inc.set(iid, { ...w908.inc.get(iid), linkedAt: 0 }) }
      w909
    }
    w897
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w910 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w911 = if (timerDef("reaction").startsOnce) {
      val w912 = ec_resumeTimer(w0, c, iid, "reaction")
      w912
    } else {
      val w913 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w914 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w915 = { ...w914, inc: w914.inc.set(iid, { ...w914.inc.get(iid), timers: w914.inc.get(iid).timers.set("reaction", { ...w914.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w916 = { ...w915, inc: w915.inc.set(iid, { ...w915.inc.get(iid), timers: w915.inc.get(iid).timers.set("reaction", { ...w915.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w916
    } else {
      val sec_917 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w918 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_917 < 0)) 0 else (c.now + (sec_917 * 1000))) }) }) }
      val w919 = { ...w918, inc: w918.inc.set(iid, { ...w918.inc.get(iid), timers: w918.inc.get(iid).timers.set("reaction", { ...w918.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w920 = { ...w919, inc: w919.inc.set(iid, { ...w919.inc.get(iid), timers: w919.inc.get(iid).timers.set("reaction", { ...w919.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w921 = { ...w920, inc: w920.inc.set(iid, { ...w920.inc.get(iid), timers: w920.inc.get(iid).timers.set("reaction", { ...w920.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w921
    }
      w913
    }
      w911
    }
    w910
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
    { val ps_922 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_922.length() > 0) and isDone(ps_922[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_923 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w924 = if ((ps_923.length() > 0)) {
      val w925 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_923[0].closeResultId }) }
      val w926 = { ...w925, inc: w925.inc.set(iid, { ...w925.inc.get(iid), closeCauseId: ps_923[0].closeCauseId }) }
      val w927 = { ...w926, inc: w926.inc.set(iid, { ...w926.inc.get(iid), result: ps_923[0].result }) }
      val w928 = { ...w927, inc: w927.inc.set(iid, { ...w927.inc.get(iid), closedBy: ps_923[0].closedBy }) }
      val w929 = { ...w928, inc: w928.inc.set(iid, { ...w928.inc.get(iid), owner: ps_923[0].closedBy }) }
      w929
    } else w0
    w924
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w930 = if (not(timerDef("resolution").pausable)) {
      val w931 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w932 = { ...w931, inc: w931.inc.set(iid, { ...w931.inc.get(iid), timers: w931.inc.get(iid).timers.set("resolution", { ...w931.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w932
    } else {
      val w933 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w934 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w935 = { ...w934, inc: w934.inc.set(iid, { ...w934.inc.get(iid), timers: w934.inc.get(iid).timers.set("resolution", { ...w934.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w936 = { ...w935, inc: w935.inc.set(iid, { ...w935.inc.get(iid), timers: w935.inc.get(iid).timers.set("resolution", { ...w935.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w936
    } else w0
      w933
    }
    w930
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_937 = c.now
    val w938 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_937 }) }
    w938
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
    { val ps_939 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_940 = (if (((ps_939.length() > 0) and not(isDone(ps_939[0])))) addressee(ps_939[0]) else "")  ((who_940 != "") and (hasAccess(who_940, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_941 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w942 = if (((ps_941.length() > 0) and (leftOf(ps_941[0], "resolution", c.now) >= 0))) {
      val w943 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w944 = { ...w943, inc: w943.inc.set(iid, { ...w943.inc.get(iid), timers: w943.inc.get(iid).timers.set("resolution", { ...w943.inc.get(iid).timers.get("resolution"), left: leftOf(ps_941[0], "resolution", c.now) }) }) }
      val w945 = { ...w944, inc: w944.inc.set(iid, { ...w944.inc.get(iid), timers: w944.inc.get(iid).timers.set("resolution", { ...w944.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w946 = if ((leftOf(ps_941[0], "resolution", c.now) == 0)) {
      val w947 = { ...w945, inc: w945.inc.set(iid, { ...w945.inc.get(iid), timers: w945.inc.get(iid).timers.set("resolution", { ...w945.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_941[0], "resolution", c.now)) ps_941[0].timers.get("resolution").fired else ps_941[0].timers.get("resolution").due) }) }) }
      w947
    } else w945
      w946
    } else w0
    w942
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w948 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_949 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w950 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w951 = { ...w950, inc: w950.inc.set(iid, { ...w950.inc.get(iid), linkedTo: "" }) }
      val w952 = { ...w951, inc: w951.inc.set(iid, { ...w951.inc.get(iid), linkedAt: 0 }) }
      val w953 = if (((ps_949.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w952 else w952
      val w954 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w955 = ps_949.foldl([], (acc, x958) => acc.append(x958.id)).foldl(w953, (wf956, pId957) => wf956)
      w955
    } else w953
      w954
    } else {
      val w959 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w960 = { ...w959, inc: w959.inc.set(iid, { ...w959.inc.get(iid), linkedAt: 0 }) }
      w960
    }
    w948
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w961 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w962 = if (timerDef("reaction").startsOnce) {
      val w963 = ec_resumeTimer(w0, c, iid, "reaction")
      w963
    } else {
      val w964 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w965 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w966 = { ...w965, inc: w965.inc.set(iid, { ...w965.inc.get(iid), timers: w965.inc.get(iid).timers.set("reaction", { ...w965.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w967 = { ...w966, inc: w966.inc.set(iid, { ...w966.inc.get(iid), timers: w966.inc.get(iid).timers.set("reaction", { ...w966.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w967
    } else {
      val sec_968 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w969 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_968 < 0)) 0 else (c.now + (sec_968 * 1000))) }) }) }
      val w970 = { ...w969, inc: w969.inc.set(iid, { ...w969.inc.get(iid), timers: w969.inc.get(iid).timers.set("reaction", { ...w969.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w971 = { ...w970, inc: w970.inc.set(iid, { ...w970.inc.get(iid), timers: w970.inc.get(iid).timers.set("reaction", { ...w970.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w972 = { ...w971, inc: w971.inc.set(iid, { ...w971.inc.get(iid), timers: w971.inc.get(iid).timers.set("reaction", { ...w971.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w972
    }
      w964
    }
      w962
    }
    w961
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_973 = settings.alerts.target
    val w974 = if (((whom_973 != "") and (whom_973 != c.actor))) w0 else w0
    w974
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
      settings.holdReasons.foldl(false, (acc, r_975) => acc or ((r_975.id == c.form.reasonId) and (r_975.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      offersTransferTo(c.me, c.form.targetId, world.inc.get(iid)),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_976) => acc and (isDone(e_976) or hasAccess(c.form.targetId, e_976))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_977) => acc or (i_977.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_978) => acc or ((i_978.id == c.form.resultId) and stepsOk(i_978, world.inc.get(iid)))),
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
    ["in_progress"].foldl(false, (acc, y979) => acc or y979 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_980) => acc or ((s_980.id == agentState(c.me)) and s_980.readOnly))),
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
  // Сценарий без графа (§14.5): два сценария, у каждого два шага; пройден — отвечены оба (набор closing)
  pure val SCENARIOS: Set[str] = Set("fire", "water")
  pure val STEPS: Set[str] = Set("s1", "s2")
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
  // иначе эти права не действуют (EXIT_RULE из машины, PROC-73). Проверка при входе — в модели действует всегда
  pure def permsAct(ps: Set[str], perm: str): bool = all {
    ps.contains(perm),
    not(EXIT_RULE.disables.contains(perm) and EXIT_RULE.appliesTo.exists(p => ps.contains(p)) and not(EXIT_RULE.requiresAnyOf.exists(p => ps.contains(p)))),
  }
  def can(who: str, perm: str): bool = OPERATORS.contains(who) and permsAct(cfg.perms.get(who), perm)
  def access(who: str, x: Incident): bool = OPERATORS.contains(who) and cfg.access.get(who).contains(x.id)
  def isOperator(id: str): bool = OPERATORS.contains(id)
  def isGroup(id: str): bool = GROUPS.contains(id)
  def members(g: str): List[str] = if (isGroup(g)) OPERATOR_LIST.select(m => cfg.members.get(g).contains(m)) else []
  def dutyGroups: List[str] = GROUP_LIST
  // Кому вообще можно передавать: люди и дежурные группы (§8.1, BUG-85)
  def transferTargets: List[str] = OPERATOR_LIST.concat(GROUP_LIST)
  // Групп устройств в модели нет: строк overrides по sourceGroup в машине тоже нет
  def inSourceGroup(x: Incident, g: str): bool = false
  def agentState(who: str): str = if (OPERATORS.contains(who)) agents.get(who) else "offline"
  def idleSec(who: str): int = if (OPERATORS.contains(who)) (clock - lastBeat.get(who)) / 1000 else 0
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
    { name: name, actor: actor, incident: i, kind: kind, form: NO_FORM, surface: "", others: [], prio: 0, scenario: "" }

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

  action create(i: str, sc: str, prio: int): bool = {
    val t = ofTrigger("event")[0]
    val w0 = { ...world,
      inc: world.inc.set(i, { ...NO_INCIDENT, id: i, number: i, eventType: "fire", priority: prio, occurredAt: clock, scenario: sc }),
      answers: world.answers.set(i, Set()) }
    all {
      incOf(i).state == "",
      commit({ ...act0("create", t.id, DISPATCHER, i), prio: prio, scenario: sc }, trApply(t.id, ctx(DISPATCHER, DISPATCHER, NO_FORM, ""), i, w0)),
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

  // Ответ на шаг сценария (§10.4): кто может — scenarioEdit машины
  action answer(a: str, i: str, st: str): bool = all {
    sees(a, i),
    scenarioEditOk(ctx(a, a, NO_FORM, "card"), i),
    not(world.answers.get(i).contains(st)),
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
    nondet sc = SCENARIOS.oneOf()
    nondet prio = PRIORITIES.oneOf()
    create(i, sc, prio)
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
  action answerAny(a: str, i: str): bool = {
    nondet st = STEPS.oneOf()
    answer(a, i, st)
  }

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
      // Срок удержания идёт, только если он у причины есть (holdSec ≥ 0)
      else if (s == "on_hold") (runs(h) iff holdSec(x) >= 0) and not(runs(z)) and z.paused and not(runs(r))
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
  //     idleReleaseSec — сейчас уходит в очередь (PROC-45)
  val silentOwnerHandled = INCIDENTS.forall(i => {
    val x = incOf(i)
    val idle = if (OPERATORS.contains(x.owner) and agentState(x.owner) != "offline") idleSec(x.owner) else 0
    all {
      (x.state == "in_progress" and idle >= settings.session.idleHoldSec) implies fixReady(i, Set("system_hold_idle")),
      (x.state == "on_hold" and x.holdReasonId != NOBODY and not(HOLD_REASONS_BY_OPERATOR.contains(x.holdReasonId)) and idle >= settings.session.idleReleaseSec) implies fixReady(i, Set("system_release_idle")),
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
    // Оговорка до решения RULE-136: из выходов у владельца только «Отложить», а лимит отложенных задан, — его может
    // закрыть лимит (§10.2), и выхода нет; правила это пока допускают
    val holdOnlyUnderLimit = EXIT_RULE.requiresAnyOf.filter(p => can(a, p)) == Set("incident:hold") and settings.limits.maxOnHold > 0
    (x.state == "in_progress" and OPERATORS.contains(a) and agentState(a) == "ready" and sees(a, i)
      and EXIT_RULE.requiresAnyOf.exists(p => can(a, p)) and not(holdOnlyUnderLimit)) implies or {
      HOLD_REASONS_BY_OPERATOR.exists(r => exitOk(a, "hold", i, exitForm(r, ""))),
      HOLD_REASONS_BY_OPERATOR.exists(r => exitOk(a, "release", i, exitForm(r, ""))),
      CLOSE_RESULT_IDS.exists(r => exitOk(a, "close", i, exitForm("", r))),
    }
  })

  // 23. Системный переход — только по делу (PROC-84): исправляющий переход сделан, только если до шага (prev) было что
  //     исправлять — адресат без доступа, не может принять, вышел; владелец вышел или на перерыве. Доступ и право
  //     принять у дежурной группы — у кого-то из участников (§5, §8.1)
  def hadPermOf(m: str, p: str): bool = permsAct(prev.cfg.perms.get(m), p)
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
    systemOnlyWhenDue,
    closedKept,
    holdDeadlineByReason,
    breakFromReady,
    levelOnlyByEscalation,
    breachesKept,
    resolutionLeftKept,
    noFixAfterAction,
    exitExists,
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
}
