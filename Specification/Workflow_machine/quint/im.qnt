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

  type HoldReason = { id: str, maxMinutes: List[int], setBy: str }

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
    holdReasons: [{ id: "third_party", maxMinutes: [30], setBy: "operator" }, { id: "patrol", maxMinutes: [45], setBy: "operator" }, { id: "no_data", maxMinutes: [60], setBy: "operator" }, { id: "break", maxMinutes: [30], setBy: "system" }, { id: "no_link", maxMinutes: [], setBy: "system" }],
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

  // §4. Срок удержания, с — по причине (secFrom таймера hold); причины нет или у неё нет срока (maxMinutes: null, RULE-116) — -1, срок не ставится

  def holdSec(x: Incident): int =
    { val rs_46 = settings.holdReasons.select(r_47 => (r_47.id == x.holdReasonId))  (if (((rs_46.length() > 0) and (rs_46[0].maxMinutes.length() > 0))) (rs_46[0].maxMinutes[0] * 60) else (0 - 1)) }

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
      val keep_92 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w93 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_92) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w94 = { ...w93, inc: w93.inc.set(iid, { ...w93.inc.get(iid), timers: w93.inc.get(iid).timers.set("reaction", { ...w93.inc.get(iid).timers.get("reaction"), paused: keep_92 }) }) }
      val w95 = { ...w94, inc: w94.inc.set(iid, { ...w94.inc.get(iid), timers: w94.inc.get(iid).timers.set("reaction", { ...w94.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w96 = { ...w95, inc: w95.inc.set(iid, { ...w95.inc.get(iid), timers: w95.inc.get(iid).timers.set("reaction", { ...w95.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w96
    }
    w90
  }

  def e_claim_2(w0: World, c: Ctx, iid: str): World = {
    val w97 = if (not(timerDef("resolution").pausable)) {
      val sec_98 = timerSec(w0.inc.get(iid), "resolution", "")
      val w99 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_98 < 0)) 0 else (c.now + (sec_98 * 1000))) }) }) }
      val w100 = { ...w99, inc: w99.inc.set(iid, { ...w99.inc.get(iid), timers: w99.inc.get(iid).timers.set("resolution", { ...w99.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w100
    } else {
      val w101 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_102 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w103 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_102 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_102)) }) }) }
      val w104 = { ...w103, inc: w103.inc.set(iid, { ...w103.inc.get(iid), timers: w103.inc.get(iid).timers.set("resolution", { ...w103.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w105 = { ...w104, inc: w104.inc.set(iid, { ...w104.inc.get(iid), timers: w104.inc.get(iid).timers.set("resolution", { ...w104.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w105
    } else w0
      w101
    }
    w97
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
    not(settings.session.states.foldl(false, (acc, s_106) => acc or ((s_106.id == agentState(c.me)) and s_106.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_accept_0(w0: World, c: Ctx, iid: str): World = {
    val who_107 = c.actor
    val w108 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_107 }) }
    w108
  }

  def e_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_109 = ""
    val w110 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_109 }) }
    w110
  }

  def e_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w111 = if (timerDef("reaction").startsOnce) {
      val w112 = ec_pauseTimer(w0, c, iid, "reaction")
      w112
    } else {
      val keep_113 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w114 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_113) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w115 = { ...w114, inc: w114.inc.set(iid, { ...w114.inc.get(iid), timers: w114.inc.get(iid).timers.set("reaction", { ...w114.inc.get(iid).timers.get("reaction"), paused: keep_113 }) }) }
      val w116 = { ...w115, inc: w115.inc.set(iid, { ...w115.inc.get(iid), timers: w115.inc.get(iid).timers.set("reaction", { ...w115.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w117 = { ...w116, inc: w116.inc.set(iid, { ...w116.inc.get(iid), timers: w116.inc.get(iid).timers.set("reaction", { ...w116.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w117
    }
    w111
  }

  def e_accept_3(w0: World, c: Ctx, iid: str): World = {
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
    not(settings.session.states.foldl(false, (acc, s_127) => acc or ((s_127.id == agentState(c.me)) and s_127.readOnly))),
  }

  def e_reject_0(w0: World, c: Ctx, iid: str): World = {
    val who_128 = ""
    val w129 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_128 }) }
    w129
  }

  def e_reject_1(w0: World, c: Ctx, iid: str): World = {
    val group_130 = ""
    val w131 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_130 }) }
    w131
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
    not(settings.session.states.foldl(false, (acc, s_132) => acc or ((s_132.id == agentState(c.me)) and s_132.readOnly))),
    ((settings.limits.maxOnHold == 0) or (countMine(incs(world), c.me, "on_hold", world.inc.get(iid).id) < settings.limits.maxOnHold)),
  }

  def e_hold_0(w0: World, c: Ctx, iid: str): World = {
    val reason_133 = c.form.reasonId
    val w134 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_133 }) }
    w134
  }

  def e_hold_1(w0: World, c: Ctx, iid: str): World = {
    val w135 = if (not(timerDef("resolution").pausable)) {
      val w136 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w137 = { ...w136, inc: w136.inc.set(iid, { ...w136.inc.get(iid), timers: w136.inc.get(iid).timers.set("resolution", { ...w136.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w137
    } else {
      val w138 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w139 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w140 = { ...w139, inc: w139.inc.set(iid, { ...w139.inc.get(iid), timers: w139.inc.get(iid).timers.set("resolution", { ...w139.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w141 = { ...w140, inc: w140.inc.set(iid, { ...w140.inc.get(iid), timers: w140.inc.get(iid).timers.set("resolution", { ...w140.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w141
    } else w0
      w138
    }
    w135
  }

  def e_hold_2(w0: World, c: Ctx, iid: str): World = {
    val w142 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w143 = if (timerDef("hold").startsOnce) {
      val w144 = ec_resumeTimer(w0, c, iid, "hold")
      w144
    } else {
      val w145 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w146 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w147 = { ...w146, inc: w146.inc.set(iid, { ...w146.inc.get(iid), timers: w146.inc.get(iid).timers.set("hold", { ...w146.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w148 = { ...w147, inc: w147.inc.set(iid, { ...w147.inc.get(iid), timers: w147.inc.get(iid).timers.set("hold", { ...w147.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w148
    } else {
      val sec_149 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w150 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_149 < 0)) 0 else (c.now + (sec_149 * 1000))) }) }) }
      val w151 = { ...w150, inc: w150.inc.set(iid, { ...w150.inc.get(iid), timers: w150.inc.get(iid).timers.set("hold", { ...w150.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w152 = { ...w151, inc: w151.inc.set(iid, { ...w151.inc.get(iid), timers: w151.inc.get(iid).timers.set("hold", { ...w151.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w153 = { ...w152, inc: w152.inc.set(iid, { ...w152.inc.get(iid), timers: w152.inc.get(iid).timers.set("hold", { ...w152.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w153
    }
      w145
    }
      w143
    }
    w142
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
    not(settings.session.states.foldl(false, (acc, s_154) => acc or ((s_154.id == agentState(c.me)) and s_154.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_resume_0(w0: World, c: Ctx, iid: str): World = {
    val w155 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w155
  }

  def e_resume_1(w0: World, c: Ctx, iid: str): World = {
    val w156 = if (timerDef("hold").startsOnce) {
      val w157 = ec_pauseTimer(w0, c, iid, "hold")
      w157
    } else {
      val keep_158 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w159 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_158) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w160 = { ...w159, inc: w159.inc.set(iid, { ...w159.inc.get(iid), timers: w159.inc.get(iid).timers.set("hold", { ...w159.inc.get(iid).timers.get("hold"), paused: keep_158 }) }) }
      val w161 = { ...w160, inc: w160.inc.set(iid, { ...w160.inc.get(iid), timers: w160.inc.get(iid).timers.set("hold", { ...w160.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w162 = { ...w161, inc: w161.inc.set(iid, { ...w161.inc.get(iid), timers: w161.inc.get(iid).timers.set("hold", { ...w161.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w162
    }
    w156
  }

  def e_resume_2(w0: World, c: Ctx, iid: str): World = {
    val w163 = if (not(timerDef("resolution").pausable)) {
      val sec_164 = timerSec(w0.inc.get(iid), "resolution", "")
      val w165 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_164 < 0)) 0 else (c.now + (sec_164 * 1000))) }) }) }
      val w166 = { ...w165, inc: w165.inc.set(iid, { ...w165.inc.get(iid), timers: w165.inc.get(iid).timers.set("resolution", { ...w165.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w166
    } else {
      val w167 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_168 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w169 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_168 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_168)) }) }) }
      val w170 = { ...w169, inc: w169.inc.set(iid, { ...w169.inc.get(iid), timers: w169.inc.get(iid).timers.set("resolution", { ...w169.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w171 = { ...w170, inc: w170.inc.set(iid, { ...w170.inc.get(iid), timers: w170.inc.get(iid).timers.set("resolution", { ...w170.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w171
    } else w0
      w167
    }
    w163
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
    not(settings.session.states.foldl(false, (acc, s_172) => acc or ((s_172.id == agentState(c.me)) and s_172.readOnly))),
  }

  def e_release_0(w0: World, c: Ctx, iid: str): World = {
    val who_173 = ""
    val w174 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_173 }) }
    w174
  }

  def e_release_1(w0: World, c: Ctx, iid: str): World = {
    val w175 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w175
  }

  def e_release_2(w0: World, c: Ctx, iid: str): World = {
    val w176 = if (not(timerDef("resolution").pausable)) {
      val w177 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w178 = { ...w177, inc: w177.inc.set(iid, { ...w177.inc.get(iid), timers: w177.inc.get(iid).timers.set("resolution", { ...w177.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w178
    } else {
      val w179 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w180 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w181 = { ...w180, inc: w180.inc.set(iid, { ...w180.inc.get(iid), timers: w180.inc.get(iid).timers.set("resolution", { ...w180.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w182 = { ...w181, inc: w181.inc.set(iid, { ...w181.inc.get(iid), timers: w181.inc.get(iid).timers.set("resolution", { ...w181.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w182
    } else w0
      w179
    }
    w176
  }

  def e_release_3(w0: World, c: Ctx, iid: str): World = {
    val w183 = if (timerDef("hold").startsOnce) {
      val w184 = ec_pauseTimer(w0, c, iid, "hold")
      w184
    } else {
      val keep_185 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w186 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_185) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w187 = { ...w186, inc: w186.inc.set(iid, { ...w186.inc.get(iid), timers: w186.inc.get(iid).timers.set("hold", { ...w186.inc.get(iid).timers.get("hold"), paused: keep_185 }) }) }
      val w188 = { ...w187, inc: w187.inc.set(iid, { ...w187.inc.get(iid), timers: w187.inc.get(iid).timers.set("hold", { ...w187.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w189 = { ...w188, inc: w188.inc.set(iid, { ...w188.inc.get(iid), timers: w188.inc.get(iid).timers.set("hold", { ...w188.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w189
    }
    w183
  }

  def e_release_4(w0: World, c: Ctx, iid: str): World = {
    val w190 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w191 = if (timerDef("reaction").startsOnce) {
      val w192 = ec_resumeTimer(w0, c, iid, "reaction")
      w192
    } else {
      val w193 = if ((("continue" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w194 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w195 = { ...w194, inc: w194.inc.set(iid, { ...w194.inc.get(iid), timers: w194.inc.get(iid).timers.set("reaction", { ...w194.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w196 = { ...w195, inc: w195.inc.set(iid, { ...w195.inc.get(iid), timers: w195.inc.get(iid).timers.set("reaction", { ...w195.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w196
    } else {
      val sec_197 = timerSec(w0.inc.get(iid), "reaction", (if (("continue" == "continue")) "" else "continue"))
      val w198 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_197 < 0)) 0 else (c.now + (sec_197 * 1000))) }) }) }
      val w199 = { ...w198, inc: w198.inc.set(iid, { ...w198.inc.get(iid), timers: w198.inc.get(iid).timers.set("reaction", { ...w198.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w200 = { ...w199, inc: w199.inc.set(iid, { ...w199.inc.get(iid), timers: w199.inc.get(iid).timers.set("reaction", { ...w199.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w201 = { ...w200, inc: w200.inc.set(iid, { ...w200.inc.get(iid), timers: w200.inc.get(iid).timers.set("reaction", { ...w200.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w201
    }
      w193
    }
      w191
    }
    w190
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
    not(settings.session.states.foldl(false, (acc, s_202) => acc or ((s_202.id == agentState(c.me)) and s_202.readOnly))),
    transferTargets.foldl(false, (acc, t_203) => acc or (((not(isSelf(c.me, t_203)) and (t_203 != addressee(world.inc.get(iid)))) and canAccept(t_203, world.inc.get(iid), "")) and linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_204) => acc and (isDone(e_204) or hasAccess(t_203, e_204))))),
    not(isSelf(c.me, c.form.targetId)),
    ((c.form.targetId == "") or hasAccess(c.form.targetId, world.inc.get(iid))),
    ((c.form.targetId == "") or linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_205) => acc and (isDone(e_205) or hasAccess(c.form.targetId, e_205)))),
    ((c.form.targetId == "") or canAccept(c.form.targetId, world.inc.get(iid), "")),
  }

  def e_transfer_0(w0: World, c: Ctx, iid: str): World = {
    val who_206 = personOf(c.form.targetId)
    val w207 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_206 }) }
    w207
  }

  def e_transfer_1(w0: World, c: Ctx, iid: str): World = {
    val group_208 = groupOf(c.form.targetId)
    val w209 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_208 }) }
    w209
  }

  def e_transfer_2(w0: World, c: Ctx, iid: str): World = {
    val w210 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), transferCount: (w0.inc.get(iid).transferCount + 1) }) }
    w210
  }

  def e_transfer_3(w0: World, c: Ctx, iid: str): World = {
    val w211 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w211
  }

  def e_transfer_4(w0: World, c: Ctx, iid: str): World = {
    val w212 = if (not(timerDef("resolution").pausable)) {
      val w213 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w214 = { ...w213, inc: w213.inc.set(iid, { ...w213.inc.get(iid), timers: w213.inc.get(iid).timers.set("resolution", { ...w213.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w214
    } else {
      val w215 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w216 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w217 = { ...w216, inc: w216.inc.set(iid, { ...w216.inc.get(iid), timers: w216.inc.get(iid).timers.set("resolution", { ...w216.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w218 = { ...w217, inc: w217.inc.set(iid, { ...w217.inc.get(iid), timers: w217.inc.get(iid).timers.set("resolution", { ...w217.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w218
    } else w0
      w215
    }
    w212
  }

  def e_transfer_5(w0: World, c: Ctx, iid: str): World = {
    val w219 = if (timerDef("hold").startsOnce) {
      val w220 = ec_pauseTimer(w0, c, iid, "hold")
      w220
    } else {
      val keep_221 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w222 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_221) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w223 = { ...w222, inc: w222.inc.set(iid, { ...w222.inc.get(iid), timers: w222.inc.get(iid).timers.set("hold", { ...w222.inc.get(iid).timers.get("hold"), paused: keep_221 }) }) }
      val w224 = { ...w223, inc: w223.inc.set(iid, { ...w223.inc.get(iid), timers: w223.inc.get(iid).timers.set("hold", { ...w223.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w225 = { ...w224, inc: w224.inc.set(iid, { ...w224.inc.get(iid), timers: w224.inc.get(iid).timers.set("hold", { ...w224.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w225
    }
    w219
  }

  def e_transfer_6(w0: World, c: Ctx, iid: str): World = {
    val w226 = if ((true and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w227 = if (timerDef("reaction").startsOnce) {
      val w228 = ec_resumeTimer(w0, c, iid, "reaction")
      w228
    } else {
      val w229 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w230 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w231 = { ...w230, inc: w230.inc.set(iid, { ...w230.inc.get(iid), timers: w230.inc.get(iid).timers.set("reaction", { ...w230.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w232 = { ...w231, inc: w231.inc.set(iid, { ...w231.inc.get(iid), timers: w231.inc.get(iid).timers.set("reaction", { ...w231.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w232
    } else {
      val sec_233 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w234 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_233 < 0)) 0 else (c.now + (sec_233 * 1000))) }) }) }
      val w235 = { ...w234, inc: w234.inc.set(iid, { ...w234.inc.get(iid), timers: w234.inc.get(iid).timers.set("reaction", { ...w234.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w236 = { ...w235, inc: w235.inc.set(iid, { ...w235.inc.get(iid), timers: w235.inc.get(iid).timers.set("reaction", { ...w235.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w237 = { ...w236, inc: w236.inc.set(iid, { ...w236.inc.get(iid), timers: w236.inc.get(iid).timers.set("reaction", { ...w236.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w237
    }
      w229
    }
      w227
    }
    w226
  }

  def e_transfer_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_8(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_transfer_9(w0: World, c: Ctx, iid: str): World = {
    val whom_238 = c.before.owner
    val w239 = if (((whom_238 != "") and (whom_238 != c.actor))) w0 else w0
    w239
  }

  def e_transfer_10(w0: World, c: Ctx, iid: str): World = {
    val whom_240 = addressee(w0.inc.get(iid))
    val w241 = if (((whom_240 != "") and (whom_240 != c.actor))) w0 else w0
    w241
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
    not(settings.session.states.foldl(false, (acc, s_242) => acc or ((s_242.id == agentState(c.me)) and s_242.readOnly))),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_takeover_0(w0: World, c: Ctx, iid: str): World = {
    val who_243 = c.actor
    val w244 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_243 }) }
    w244
  }

  def e_takeover_1(w0: World, c: Ctx, iid: str): World = {
    val group_245 = ""
    val w246 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_245 }) }
    w246
  }

  def e_takeover_2(w0: World, c: Ctx, iid: str): World = {
    val w247 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w247
  }

  def e_takeover_3(w0: World, c: Ctx, iid: str): World = {
    val w248 = if (timerDef("reaction").startsOnce) {
      val w249 = ec_pauseTimer(w0, c, iid, "reaction")
      w249
    } else {
      val keep_250 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w251 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_250) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w252 = { ...w251, inc: w251.inc.set(iid, { ...w251.inc.get(iid), timers: w251.inc.get(iid).timers.set("reaction", { ...w251.inc.get(iid).timers.get("reaction"), paused: keep_250 }) }) }
      val w253 = { ...w252, inc: w252.inc.set(iid, { ...w252.inc.get(iid), timers: w252.inc.get(iid).timers.set("reaction", { ...w252.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w254 = { ...w253, inc: w253.inc.set(iid, { ...w253.inc.get(iid), timers: w253.inc.get(iid).timers.set("reaction", { ...w253.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w254
    }
    w248
  }

  def e_takeover_4(w0: World, c: Ctx, iid: str): World = {
    val w255 = if (timerDef("hold").startsOnce) {
      val w256 = ec_pauseTimer(w0, c, iid, "hold")
      w256
    } else {
      val keep_257 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w258 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_257) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w259 = { ...w258, inc: w258.inc.set(iid, { ...w258.inc.get(iid), timers: w258.inc.get(iid).timers.set("hold", { ...w258.inc.get(iid).timers.get("hold"), paused: keep_257 }) }) }
      val w260 = { ...w259, inc: w259.inc.set(iid, { ...w259.inc.get(iid), timers: w259.inc.get(iid).timers.set("hold", { ...w259.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w261 = { ...w260, inc: w260.inc.set(iid, { ...w260.inc.get(iid), timers: w260.inc.get(iid).timers.set("hold", { ...w260.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w261
    }
    w255
  }

  def e_takeover_5(w0: World, c: Ctx, iid: str): World = {
    val w262 = if (not(timerDef("resolution").pausable)) {
      val sec_263 = timerSec(w0.inc.get(iid), "resolution", "")
      val w264 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if ((sec_263 < 0)) 0 else (c.now + (sec_263 * 1000))) }) }) }
      val w265 = { ...w264, inc: w264.inc.set(iid, { ...w264.inc.get(iid), timers: w264.inc.get(iid).timers.set("resolution", { ...w264.inc.get(iid).timers.get("resolution"), since: c.now }) }) }
      w265
    } else {
      val w266 = if ((w0.inc.get(iid).timers.get("resolution").due == 0)) {
      val left_267 = (if (w0.inc.get(iid).timers.get("resolution").paused) w0.inc.get(iid).timers.get("resolution").left else (timerSec(w0.inc.get(iid), "resolution", "") * 1000))
      val w268 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (if (((left_267 == 0) and (w0.inc.get(iid).timers.get("resolution").fired != 0))) w0.inc.get(iid).timers.get("resolution").fired else (c.now + left_267)) }) }) }
      val w269 = { ...w268, inc: w268.inc.set(iid, { ...w268.inc.get(iid), timers: w268.inc.get(iid).timers.set("resolution", { ...w268.inc.get(iid).timers.get("resolution"), paused: false }) }) }
      val w270 = { ...w269, inc: w269.inc.set(iid, { ...w269.inc.get(iid), timers: w269.inc.get(iid).timers.set("resolution", { ...w269.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
      w270
    } else w0
      w266
    }
    w262
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
    val whom_271 = c.before.owner
    val w272 = if (((whom_271 != "") and (whom_271 != c.actor))) w0 else w0
    w272
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
    not(settings.session.states.foldl(false, (acc, s_273) => acc or ((s_273.id == agentState(c.me)) and s_273.readOnly))),
    { val os_274 = closeOptions(c.me, world.inc.get(iid), c.surface)  (if ((c.form.resultId != "")) os_274.foldl(false, (acc, o_275) => acc or ((o_275.id == c.form.resultId) and stepsOk(o_275, world.inc.get(iid)))) else os_274.foldl(false, (acc, o_276) => acc or stepsOk(o_276, world.inc.get(iid)))) },
  }

  def e_close_0(w0: World, c: Ctx, iid: str): World = {
    val who_277 = c.actor
    val w278 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_277 }) }
    w278
  }

  def e_close_1(w0: World, c: Ctx, iid: str): World = {
    val group_279 = ""
    val w280 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_279 }) }
    w280
  }

  def e_close_2(w0: World, c: Ctx, iid: str): World = {
    val value_281 = c.actor
    val w282 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_281 }) }
    w282
  }

  def e_close_3(w0: World, c: Ctx, iid: str): World = {
    val value_283 = c.now
    val w284 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_283 }) }
    w284
  }

  def e_close_4(w0: World, c: Ctx, iid: str): World = {
    val value_285 = c.form.resultId
    val w286 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_285 }) }
    w286
  }

  def e_close_5(w0: World, c: Ctx, iid: str): World = {
    val value_287 = c.form.causeId
    val w288 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_287 }) }
    w288
  }

  def e_close_6(w0: World, c: Ctx, iid: str): World = {
    val value_289 = c.form.comment
    val w290 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_289 }) }
    w290
  }

  def e_close_7(w0: World, c: Ctx, iid: str): World = {
    val w291 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w291
  }

  def e_close_8(w0: World, c: Ctx, iid: str): World = {
    val w292 = if (timerDef("reaction").startsOnce) {
      val w293 = ec_pauseTimer(w0, c, iid, "reaction")
      w293
    } else {
      val keep_294 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w295 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_294) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w296 = { ...w295, inc: w295.inc.set(iid, { ...w295.inc.get(iid), timers: w295.inc.get(iid).timers.set("reaction", { ...w295.inc.get(iid).timers.get("reaction"), paused: keep_294 }) }) }
      val w297 = { ...w296, inc: w296.inc.set(iid, { ...w296.inc.get(iid), timers: w296.inc.get(iid).timers.set("reaction", { ...w296.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w298 = { ...w297, inc: w297.inc.set(iid, { ...w297.inc.get(iid), timers: w297.inc.get(iid).timers.set("reaction", { ...w297.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w298
    }
    w292
  }

  def e_close_9(w0: World, c: Ctx, iid: str): World = {
    val w299 = if (not(timerDef("resolution").pausable)) {
      val w300 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w301 = { ...w300, inc: w300.inc.set(iid, { ...w300.inc.get(iid), timers: w300.inc.get(iid).timers.set("resolution", { ...w300.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w301
    } else {
      val w302 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w303 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w304 = { ...w303, inc: w303.inc.set(iid, { ...w303.inc.get(iid), timers: w303.inc.get(iid).timers.set("resolution", { ...w303.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w305 = { ...w304, inc: w304.inc.set(iid, { ...w304.inc.get(iid), timers: w304.inc.get(iid).timers.set("resolution", { ...w304.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w305
    } else w0
      w302
    }
    w299
  }

  def e_close_10(w0: World, c: Ctx, iid: str): World = {
    val w306 = if (timerDef("hold").startsOnce) {
      val w307 = ec_pauseTimer(w0, c, iid, "hold")
      w307
    } else {
      val keep_308 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w309 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_308) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w310 = { ...w309, inc: w309.inc.set(iid, { ...w309.inc.get(iid), timers: w309.inc.get(iid).timers.set("hold", { ...w309.inc.get(iid).timers.get("hold"), paused: keep_308 }) }) }
      val w311 = { ...w310, inc: w310.inc.set(iid, { ...w310.inc.get(iid), timers: w310.inc.get(iid).timers.set("hold", { ...w310.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w312 = { ...w311, inc: w311.inc.set(iid, { ...w311.inc.get(iid), timers: w311.inc.get(iid).timers.set("hold", { ...w311.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w312
    }
    w306
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
    not(settings.session.states.foldl(false, (acc, s_313) => acc or ((s_313.id == agentState(c.me)) and s_313.readOnly))),
    ((c.now - world.inc.get(iid).closedAt) <= (settings.limits.reopenWindowMin * 60000)),
    ((settings.limits.maxActive == 0) or (countMine(incs(world), c.me, "in_progress", world.inc.get(iid).id) < settings.limits.maxActive)),
  }

  def e_reopen_0(w0: World, c: Ctx, iid: str): World = {
    val who_314 = c.actor
    val w315 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_314 }) }
    w315
  }

  def e_reopen_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reopen_2(w0: World, c: Ctx, iid: str): World = {
    val w316 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_317 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w318 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w319 = { ...w318, inc: w318.inc.set(iid, { ...w318.inc.get(iid), linkedTo: "" }) }
      val w320 = { ...w319, inc: w319.inc.set(iid, { ...w319.inc.get(iid), linkedAt: 0 }) }
      val w321 = if (((ps_317.length() > 0) and ("workflow.journal.reopen_unlinked" != ""))) w320 else w320
      val w322 = if (("workflow.journal.linked_reopened" != "")) {
      val w323 = ps_317.foldl([], (acc, x326) => acc.append(x326.id)).foldl(w321, (wf324, pId325) => wf324)
      w323
    } else w321
      w322
    } else {
      val w327 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w328 = { ...w327, inc: w327.inc.set(iid, { ...w327.inc.get(iid), linkedAt: 0 }) }
      w328
    }
    w316
  }

  def e_reopen_3(w0: World, c: Ctx, iid: str): World = {
    val value_329 = ""
    val w330 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: value_329 }) }
    w330
  }

  def e_reopen_4(w0: World, c: Ctx, iid: str): World = {
    val value_331 = ""
    val w332 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeCauseId: value_331 }) }
    w332
  }

  def e_reopen_5(w0: World, c: Ctx, iid: str): World = {
    val value_333 = ""
    val w334 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), result: value_333 }) }
    w334
  }

  def e_reopen_6(w0: World, c: Ctx, iid: str): World = {
    val value_335 = 0
    val w336 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_335 }) }
    w336
  }

  def e_reopen_7(w0: World, c: Ctx, iid: str): World = {
    val value_337 = ""
    val w338 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedBy: value_337 }) }
    w338
  }

  def e_reopen_8(w0: World, c: Ctx, iid: str): World = {
    val sec_339 = settings.limits.reopenResolutionSec
    val w340 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: (c.now + ((if ((sec_339 > 0)) sec_339 else norm(w0.inc.get(iid), timerDef("resolution"))) * 1000)) }) }) }
    val w341 = { ...w340, inc: w340.inc.set(iid, { ...w340.inc.get(iid), timers: w340.inc.get(iid).timers.set("resolution", { ...w340.inc.get(iid).timers.get("resolution"), paused: false }) }) }
    val w342 = { ...w341, inc: w341.inc.set(iid, { ...w341.inc.get(iid), timers: w341.inc.get(iid).timers.set("resolution", { ...w341.inc.get(iid).timers.get("resolution"), left: 0 }) }) }
    w342
  }

  def e_reopen_9(w0: World, c: Ctx, iid: str): World = {

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
    w10
  }

  // auto_escalate: timer → pending_acceptance

  def ok_auto_escalate(c: Ctx, iid: str): bool = all {
    Set("new", "pending_acceptance").contains(world.inc.get(iid).state),
    (settings.escalation.enabled == true),
    { val t_343 = world.inc.get(iid).timers.get("reaction")  (((t_343.due != 0) and (t_343.due <= c.now)) and (t_343.fired != t_343.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_auto_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val who_344 = personOf(levelUpTarget(c.before))
    val w345 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_344 }) }
    w345
  }

  def e_auto_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val group_346 = groupOf(levelUpTarget(c.before))
    val w347 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_346 }) }
    w347
  }

  def e_auto_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val value_348 = levelUpNumber(c.before)
    val w349 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_348 }) }
    w349
  }

  def e_auto_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val w350 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w350
  }

  def e_auto_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w351 = if (not(timerDef("resolution").pausable)) {
      val w352 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w353 = { ...w352, inc: w352.inc.set(iid, { ...w352.inc.get(iid), timers: w352.inc.get(iid).timers.set("resolution", { ...w352.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w353
    } else {
      val w354 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w355 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w356 = { ...w355, inc: w355.inc.set(iid, { ...w355.inc.get(iid), timers: w355.inc.get(iid).timers.set("resolution", { ...w355.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w357 = { ...w356, inc: w356.inc.set(iid, { ...w356.inc.get(iid), timers: w356.inc.get(iid).timers.set("resolution", { ...w356.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w357
    } else w0
      w354
    }
    w351
  }

  def e_auto_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w358 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w359 = if (timerDef("reaction").startsOnce) {
      val w360 = ec_resumeTimer(w0, c, iid, "reaction")
      w360
    } else {
      val w361 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w362 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w363 = { ...w362, inc: w362.inc.set(iid, { ...w362.inc.get(iid), timers: w362.inc.get(iid).timers.set("reaction", { ...w362.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w364 = { ...w363, inc: w363.inc.set(iid, { ...w363.inc.get(iid), timers: w363.inc.get(iid).timers.set("reaction", { ...w363.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w364
    } else {
      val sec_365 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w366 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_365 < 0)) 0 else (c.now + (sec_365 * 1000))) }) }) }
      val w367 = { ...w366, inc: w366.inc.set(iid, { ...w366.inc.get(iid), timers: w366.inc.get(iid).timers.set("reaction", { ...w366.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w368 = { ...w367, inc: w367.inc.set(iid, { ...w367.inc.get(iid), timers: w367.inc.get(iid).timers.set("reaction", { ...w367.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w369 = { ...w368, inc: w368.inc.set(iid, { ...w368.inc.get(iid), timers: w368.inc.get(iid).timers.set("reaction", { ...w368.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w369
    }
      w361
    }
      w359
    }
    w358
  }

  def e_auto_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_auto_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_370 = addressee(w0.inc.get(iid))
    val w371 = if (((whom_370 != "") and (whom_370 != c.actor))) w0 else w0
    w371
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
    { val t_372 = world.inc.get(iid).timers.get("reaction")  (((t_372.due != 0) and (t_372.due <= c.now)) and (t_372.fired != t_372.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_escalation_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_373 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w374 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_373) }) }
    val w375 = { ...w374, inc: w374.inc.set(iid, { ...w374.inc.get(iid), slaBreached: true }) }
    val w376 = groupMembersAt(incs(w0), w375.inc.get(iid), c.deadline).foldl([], (acc, x379) => acc.append(x379.id)).foldl(w375, (wf377, eId378) => {
      val w380 = { ...wf377, inc: wf377.inc.set(eId378, { ...wf377.inc.get(eId378), breaches: wf377.inc.get(eId378).breaches.append(breach_373) }) }
      val w381 = { ...w380, inc: w380.inc.set(eId378, { ...w380.inc.get(eId378), slaBreached: true }) }
      w381
    })
    w376
  }

  def e_escalation_ceiling_1(w0: World, c: Ctx, iid: str): World = {
    val w382 = if (timerDef("reaction").startsOnce) {
      val w383 = ec_pauseTimer(w0, c, iid, "reaction")
      w383
    } else {
      val keep_384 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w385 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_384) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w386 = { ...w385, inc: w385.inc.set(iid, { ...w385.inc.get(iid), timers: w385.inc.get(iid).timers.set("reaction", { ...w385.inc.get(iid).timers.get("reaction"), paused: keep_384 }) }) }
      val w387 = { ...w386, inc: w386.inc.set(iid, { ...w386.inc.get(iid), timers: w386.inc.get(iid).timers.set("reaction", { ...w386.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w388 = { ...w387, inc: w387.inc.set(iid, { ...w387.inc.get(iid), timers: w387.inc.get(iid).timers.set("reaction", { ...w387.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w388
    }
    w382
  }

  def e_escalation_ceiling_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_escalation_ceiling_3(w0: World, c: Ctx, iid: str): World = {
    val whom_389 = settings.alerts.target
    val w390 = if (((whom_389 != "") and (whom_389 != c.actor))) w0 else w0
    w390
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
    { val t_391 = world.inc.get(iid).timers.get("reaction")  (((t_391.due != 0) and (t_391.due <= c.now)) and (t_391.fired != t_391.due)) },
  }

  def e_reaction_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_392 = { kind: "reaction", at: c.deadline, owner: addressee(c.before) }
    val w393 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_392) }) }
    val w394 = { ...w393, inc: w393.inc.set(iid, { ...w393.inc.get(iid), slaBreached: true }) }
    val w395 = groupMembersAt(incs(w0), w394.inc.get(iid), c.deadline).foldl([], (acc, x398) => acc.append(x398.id)).foldl(w394, (wf396, eId397) => {
      val w399 = { ...wf396, inc: wf396.inc.set(eId397, { ...wf396.inc.get(eId397), breaches: wf396.inc.get(eId397).breaches.append(breach_392) }) }
      val w400 = { ...w399, inc: w399.inc.set(eId397, { ...w399.inc.get(eId397), slaBreached: true }) }
      w400
    })
    w395
  }

  def e_reaction_overdue_1(w0: World, c: Ctx, iid: str): World = {
    val w401 = if (timerDef("reaction").startsOnce) {
      val w402 = ec_pauseTimer(w0, c, iid, "reaction")
      w402
    } else {
      val keep_403 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w404 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_403) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w405 = { ...w404, inc: w404.inc.set(iid, { ...w404.inc.get(iid), timers: w404.inc.get(iid).timers.set("reaction", { ...w404.inc.get(iid).timers.get("reaction"), paused: keep_403 }) }) }
      val w406 = { ...w405, inc: w405.inc.set(iid, { ...w405.inc.get(iid), timers: w405.inc.get(iid).timers.set("reaction", { ...w405.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w407 = { ...w406, inc: w406.inc.set(iid, { ...w406.inc.get(iid), timers: w406.inc.get(iid).timers.set("reaction", { ...w406.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w407
    }
    w401
  }

  def e_reaction_overdue_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_reaction_overdue_3(w0: World, c: Ctx, iid: str): World = {
    val whom_408 = settings.alerts.target
    val w409 = if (((whom_408 != "") and (whom_408 != c.actor))) w0 else w0
    w409
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
    { val t_410 = world.inc.get(iid).timers.get("resolution")  (((t_410.due != 0) and (t_410.due <= c.now)) and (t_410.fired != t_410.due)) },
    (settings.escalation.onResolutionOverdue == "alert"),
  }

  def e_resolution_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_411 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w412 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_411) }) }
    val w413 = { ...w412, inc: w412.inc.set(iid, { ...w412.inc.get(iid), slaBreached: true }) }
    val w414 = groupMembersAt(incs(w0), w413.inc.get(iid), c.deadline).foldl([], (acc, x417) => acc.append(x417.id)).foldl(w413, (wf415, eId416) => {
      val w418 = { ...wf415, inc: wf415.inc.set(eId416, { ...wf415.inc.get(eId416), breaches: wf415.inc.get(eId416).breaches.append(breach_411) }) }
      val w419 = { ...w418, inc: w418.inc.set(eId416, { ...w418.inc.get(eId416), slaBreached: true }) }
      w419
    })
    w414
  }

  def e_resolution_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_420 = settings.alerts.target
    val w421 = if (((whom_420 != "") and (whom_420 != c.actor))) w0 else w0
    w421
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
    { val t_422 = world.inc.get(iid).timers.get("resolution")  (((t_422.due != 0) and (t_422.due <= c.now)) and (t_422.fired != t_422.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == true),
  }

  def e_resolution_escalate_0(w0: World, c: Ctx, iid: str): World = {
    val breach_423 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w424 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_423) }) }
    val w425 = { ...w424, inc: w424.inc.set(iid, { ...w424.inc.get(iid), slaBreached: true }) }
    val w426 = groupMembersAt(incs(w0), w425.inc.get(iid), c.deadline).foldl([], (acc, x429) => acc.append(x429.id)).foldl(w425, (wf427, eId428) => {
      val w430 = { ...wf427, inc: wf427.inc.set(eId428, { ...wf427.inc.get(eId428), breaches: wf427.inc.get(eId428).breaches.append(breach_423) }) }
      val w431 = { ...w430, inc: w430.inc.set(eId428, { ...w430.inc.get(eId428), slaBreached: true }) }
      w431
    })
    w426
  }

  def e_resolution_escalate_1(w0: World, c: Ctx, iid: str): World = {
    val who_432 = personOf(levelUpTarget(c.before))
    val w433 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_432 }) }
    w433
  }

  def e_resolution_escalate_2(w0: World, c: Ctx, iid: str): World = {
    val group_434 = groupOf(levelUpTarget(c.before))
    val w435 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_434 }) }
    w435
  }

  def e_resolution_escalate_3(w0: World, c: Ctx, iid: str): World = {
    val value_436 = levelUpNumber(c.before)
    val w437 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), escalationLevel: value_436 }) }
    w437
  }

  def e_resolution_escalate_4(w0: World, c: Ctx, iid: str): World = {
    val w438 = if (not(timerDef("resolution").pausable)) {
      val w439 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w440 = { ...w439, inc: w439.inc.set(iid, { ...w439.inc.get(iid), timers: w439.inc.get(iid).timers.set("resolution", { ...w439.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w440
    } else {
      val w441 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w442 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w443 = { ...w442, inc: w442.inc.set(iid, { ...w442.inc.get(iid), timers: w442.inc.get(iid).timers.set("resolution", { ...w442.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w444 = { ...w443, inc: w443.inc.set(iid, { ...w443.inc.get(iid), timers: w443.inc.get(iid).timers.set("resolution", { ...w443.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w444
    } else w0
      w441
    }
    w438
  }

  def e_resolution_escalate_5(w0: World, c: Ctx, iid: str): World = {
    val w445 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w446 = if (timerDef("reaction").startsOnce) {
      val w447 = ec_resumeTimer(w0, c, iid, "reaction")
      w447
    } else {
      val w448 = if ((("byEscalationLevel" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w449 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w450 = { ...w449, inc: w449.inc.set(iid, { ...w449.inc.get(iid), timers: w449.inc.get(iid).timers.set("reaction", { ...w449.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w451 = { ...w450, inc: w450.inc.set(iid, { ...w450.inc.get(iid), timers: w450.inc.get(iid).timers.set("reaction", { ...w450.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w451
    } else {
      val sec_452 = timerSec(w0.inc.get(iid), "reaction", (if (("byEscalationLevel" == "continue")) "" else "byEscalationLevel"))
      val w453 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_452 < 0)) 0 else (c.now + (sec_452 * 1000))) }) }) }
      val w454 = { ...w453, inc: w453.inc.set(iid, { ...w453.inc.get(iid), timers: w453.inc.get(iid).timers.set("reaction", { ...w453.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w455 = { ...w454, inc: w454.inc.set(iid, { ...w454.inc.get(iid), timers: w454.inc.get(iid).timers.set("reaction", { ...w454.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w456 = { ...w455, inc: w455.inc.set(iid, { ...w455.inc.get(iid), timers: w455.inc.get(iid).timers.set("reaction", { ...w455.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w456
    }
      w448
    }
      w446
    }
    w445
  }

  def e_resolution_escalate_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_escalate_8(w0: World, c: Ctx, iid: str): World = {
    val whom_457 = c.before.owner
    val w458 = if (((whom_457 != "") and (whom_457 != c.actor))) w0 else w0
    w458
  }

  def e_resolution_escalate_9(w0: World, c: Ctx, iid: str): World = {
    val whom_459 = addressee(w0.inc.get(iid))
    val w460 = if (((whom_459 != "") and (whom_459 != c.actor))) w0 else w0
    w460
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
    { val t_461 = world.inc.get(iid).timers.get("resolution")  (((t_461.due != 0) and (t_461.due <= c.now)) and (t_461.fired != t_461.due)) },
    ((nextLevels(world.inc.get(iid)).length() > 0) == false),
  }

  def e_resolution_ceiling_0(w0: World, c: Ctx, iid: str): World = {
    val breach_462 = { kind: "resolution", at: c.deadline, owner: addressee(c.before) }
    val w463 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_462) }) }
    val w464 = { ...w463, inc: w463.inc.set(iid, { ...w463.inc.get(iid), slaBreached: true }) }
    val w465 = groupMembersAt(incs(w0), w464.inc.get(iid), c.deadline).foldl([], (acc, x468) => acc.append(x468.id)).foldl(w464, (wf466, eId467) => {
      val w469 = { ...wf466, inc: wf466.inc.set(eId467, { ...wf466.inc.get(eId467), breaches: wf466.inc.get(eId467).breaches.append(breach_462) }) }
      val w470 = { ...w469, inc: w469.inc.set(eId467, { ...w469.inc.get(eId467), slaBreached: true }) }
      w470
    })
    w465
  }

  def e_resolution_ceiling_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_resolution_ceiling_2(w0: World, c: Ctx, iid: str): World = {
    val whom_471 = settings.alerts.target
    val w472 = if (((whom_471 != "") and (whom_471 != c.actor))) w0 else w0
    w472
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
    { val t_473 = world.inc.get(iid).timers.get("hold")  (((t_473.due != 0) and (t_473.due <= c.now)) and (t_473.fired != t_473.due)) },
  }

  def e_hold_overdue_0(w0: World, c: Ctx, iid: str): World = {
    val breach_474 = { kind: "hold", at: c.deadline, owner: addressee(c.before) }
    val w475 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), breaches: w0.inc.get(iid).breaches.append(breach_474) }) }
    val w476 = { ...w475, inc: w475.inc.set(iid, { ...w475.inc.get(iid), slaBreached: true }) }
    val w477 = groupMembersAt(incs(w0), w476.inc.get(iid), c.deadline).foldl([], (acc, x480) => acc.append(x480.id)).foldl(w476, (wf478, eId479) => {
      val w481 = { ...wf478, inc: wf478.inc.set(eId479, { ...wf478.inc.get(eId479), breaches: wf478.inc.get(eId479).breaches.append(breach_474) }) }
      val w482 = { ...w481, inc: w481.inc.set(eId479, { ...w481.inc.get(eId479), slaBreached: true }) }
      w482
    })
    w477
  }

  def e_hold_overdue_1(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_hold_overdue_2(w0: World, c: Ctx, iid: str): World = {
    val whom_483 = settings.alerts.target
    val w484 = if (((whom_483 != "") and (whom_483 != c.actor))) w0 else w0
    w484
  }

  def apply_hold_overdue(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val w1 = e_hold_overdue_0(w0, c1, iid)
    val w2 = e_hold_overdue_1(w1, c1, iid)
    val w3 = e_hold_overdue_2(w2, c1, iid)
    w3
  }

  // system_hold_break: system → on_hold

  def ok_system_hold_break(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (agentState(c.me) == "not_ready"),
  }

  def e_system_hold_break_0(w0: World, c: Ctx, iid: str): World = {
    val reason_485 = "break"
    val w486 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_485 }) }
    w486
  }

  def e_system_hold_break_1(w0: World, c: Ctx, iid: str): World = {
    val w487 = if (not(timerDef("resolution").pausable)) {
      val w488 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w489 = { ...w488, inc: w488.inc.set(iid, { ...w488.inc.get(iid), timers: w488.inc.get(iid).timers.set("resolution", { ...w488.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w489
    } else {
      val w490 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w491 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w492 = { ...w491, inc: w491.inc.set(iid, { ...w491.inc.get(iid), timers: w491.inc.get(iid).timers.set("resolution", { ...w491.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w493 = { ...w492, inc: w492.inc.set(iid, { ...w492.inc.get(iid), timers: w492.inc.get(iid).timers.set("resolution", { ...w492.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w493
    } else w0
      w490
    }
    w487
  }

  def e_system_hold_break_2(w0: World, c: Ctx, iid: str): World = {
    val w494 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w495 = if (timerDef("hold").startsOnce) {
      val w496 = ec_resumeTimer(w0, c, iid, "hold")
      w496
    } else {
      val w497 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w498 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w499 = { ...w498, inc: w498.inc.set(iid, { ...w498.inc.get(iid), timers: w498.inc.get(iid).timers.set("hold", { ...w498.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w500 = { ...w499, inc: w499.inc.set(iid, { ...w499.inc.get(iid), timers: w499.inc.get(iid).timers.set("hold", { ...w499.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w500
    } else {
      val sec_501 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w502 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_501 < 0)) 0 else (c.now + (sec_501 * 1000))) }) }) }
      val w503 = { ...w502, inc: w502.inc.set(iid, { ...w502.inc.get(iid), timers: w502.inc.get(iid).timers.set("hold", { ...w502.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w504 = { ...w503, inc: w503.inc.set(iid, { ...w503.inc.get(iid), timers: w503.inc.get(iid).timers.set("hold", { ...w503.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w505 = { ...w504, inc: w504.inc.set(iid, { ...w504.inc.get(iid), timers: w504.inc.get(iid).timers.set("hold", { ...w504.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w505
    }
      w497
    }
      w495
    }
    w494
  }

  def e_system_hold_break_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_break_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def apply_system_hold_break(c: Ctx, iid: str, w0: World): World = {
    val c1 = { ...c, before: w0.inc.get(iid) }
    val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: "on_hold" }) }
    val w1 = e_system_hold_break_0(ws, c1, iid)
    val w2 = e_system_hold_break_1(w1, c1, iid)
    val w3 = e_system_hold_break_2(w2, c1, iid)
    val w4 = e_system_hold_break_3(w3, c1, iid)
    val w5 = e_system_hold_break_4(w4, c1, iid)
    w5
  }

  // system_hold_idle: system → on_hold

  def ok_system_hold_idle(c: Ctx, iid: str): bool = all {
    Set("in_progress").contains(world.inc.get(iid).state),
    (idleSec(c.me) >= settings.session.idleHoldSec),
  }

  def e_system_hold_idle_0(w0: World, c: Ctx, iid: str): World = {
    val reason_506 = "no_link"
    val w507 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: reason_506 }) }
    w507
  }

  def e_system_hold_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w508 = if (not(timerDef("resolution").pausable)) {
      val w509 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w510 = { ...w509, inc: w509.inc.set(iid, { ...w509.inc.get(iid), timers: w509.inc.get(iid).timers.set("resolution", { ...w509.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w510
    } else {
      val w511 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w512 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w513 = { ...w512, inc: w512.inc.set(iid, { ...w512.inc.get(iid), timers: w512.inc.get(iid).timers.set("resolution", { ...w512.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w514 = { ...w513, inc: w513.inc.set(iid, { ...w513.inc.get(iid), timers: w513.inc.get(iid).timers.set("resolution", { ...w513.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w514
    } else w0
      w511
    }
    w508
  }

  def e_system_hold_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w515 = if ((false and (w0.inc.get(iid).timers.get("hold").due != 0))) w0 else {
      val w516 = if (timerDef("hold").startsOnce) {
      val w517 = ec_resumeTimer(w0, c, iid, "hold")
      w517
    } else {
      val w518 = if ((("" == "continue") and w0.inc.get(iid).timers.get("hold").paused)) {
      val w519 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (c.now + w0.inc.get(iid).timers.get("hold").left) }) }) }
      val w520 = { ...w519, inc: w519.inc.set(iid, { ...w519.inc.get(iid), timers: w519.inc.get(iid).timers.set("hold", { ...w519.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w521 = { ...w520, inc: w520.inc.set(iid, { ...w520.inc.get(iid), timers: w520.inc.get(iid).timers.set("hold", { ...w520.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w521
    } else {
      val sec_522 = timerSec(w0.inc.get(iid), "hold", (if (("" == "continue")) "" else ""))
      val w523 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), due: (if ((sec_522 < 0)) 0 else (c.now + (sec_522 * 1000))) }) }) }
      val w524 = { ...w523, inc: w523.inc.set(iid, { ...w523.inc.get(iid), timers: w523.inc.get(iid).timers.set("hold", { ...w523.inc.get(iid).timers.get("hold"), since: c.now }) }) }
      val w525 = { ...w524, inc: w524.inc.set(iid, { ...w524.inc.get(iid), timers: w524.inc.get(iid).timers.set("hold", { ...w524.inc.get(iid).timers.get("hold"), paused: false }) }) }
      val w526 = { ...w525, inc: w525.inc.set(iid, { ...w525.inc.get(iid), timers: w525.inc.get(iid).timers.set("hold", { ...w525.inc.get(iid).timers.get("hold"), left: 0 }) }) }
      w526
    }
      w518
    }
      w516
    }
    w515
  }

  def e_system_hold_idle_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_system_hold_idle_4(w0: World, c: Ctx, iid: str): World = {
    val whom_527 = settings.alerts.target
    val w528 = if (((whom_527 != "") and (whom_527 != c.actor))) w0 else w0
    w528
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
    ["break", "no_link"].foldl(false, (acc, y529) => acc or y529 == world.inc.get(iid).holdReasonId),
  }

  def e_system_release_idle_0(w0: World, c: Ctx, iid: str): World = {
    val who_530 = ""
    val w531 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_530 }) }
    w531
  }

  def e_system_release_idle_1(w0: World, c: Ctx, iid: str): World = {
    val w532 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w532
  }

  def e_system_release_idle_2(w0: World, c: Ctx, iid: str): World = {
    val w533 = if (timerDef("hold").startsOnce) {
      val w534 = ec_pauseTimer(w0, c, iid, "hold")
      w534
    } else {
      val keep_535 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w536 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_535) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w537 = { ...w536, inc: w536.inc.set(iid, { ...w536.inc.get(iid), timers: w536.inc.get(iid).timers.set("hold", { ...w536.inc.get(iid).timers.get("hold"), paused: keep_535 }) }) }
      val w538 = { ...w537, inc: w537.inc.set(iid, { ...w537.inc.get(iid), timers: w537.inc.get(iid).timers.set("hold", { ...w537.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w539 = { ...w538, inc: w538.inc.set(iid, { ...w538.inc.get(iid), timers: w538.inc.get(iid).timers.set("hold", { ...w538.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w539
    }
    w533
  }

  def e_system_release_idle_3(w0: World, c: Ctx, iid: str): World = {
    val w540 = if (not(timerDef("resolution").pausable)) {
      val w541 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w542 = { ...w541, inc: w541.inc.set(iid, { ...w541.inc.get(iid), timers: w541.inc.get(iid).timers.set("resolution", { ...w541.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w542
    } else {
      val w543 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w544 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w545 = { ...w544, inc: w544.inc.set(iid, { ...w544.inc.get(iid), timers: w544.inc.get(iid).timers.set("resolution", { ...w544.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w546 = { ...w545, inc: w545.inc.set(iid, { ...w545.inc.get(iid), timers: w545.inc.get(iid).timers.set("resolution", { ...w545.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w546
    } else w0
      w543
    }
    w540
  }

  def e_system_release_idle_4(w0: World, c: Ctx, iid: str): World = {
    val w547 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w548 = if (timerDef("reaction").startsOnce) {
      val w549 = ec_resumeTimer(w0, c, iid, "reaction")
      w549
    } else {
      val w550 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w551 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w552 = { ...w551, inc: w551.inc.set(iid, { ...w551.inc.get(iid), timers: w551.inc.get(iid).timers.set("reaction", { ...w551.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w553 = { ...w552, inc: w552.inc.set(iid, { ...w552.inc.get(iid), timers: w552.inc.get(iid).timers.set("reaction", { ...w552.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w553
    } else {
      val sec_554 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w555 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_554 < 0)) 0 else (c.now + (sec_554 * 1000))) }) }) }
      val w556 = { ...w555, inc: w555.inc.set(iid, { ...w555.inc.get(iid), timers: w555.inc.get(iid).timers.set("reaction", { ...w555.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w557 = { ...w556, inc: w556.inc.set(iid, { ...w556.inc.get(iid), timers: w556.inc.get(iid).timers.set("reaction", { ...w556.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w558 = { ...w557, inc: w557.inc.set(iid, { ...w557.inc.get(iid), timers: w557.inc.get(iid).timers.set("reaction", { ...w557.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w558
    }
      w550
    }
      w548
    }
    w547
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

  // addressee_signed_out_to_group: system → pending_acceptance

  def ok_addressee_signed_out_to_group(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance").contains(world.inc.get(iid).state),
    (agentState(c.me) == "offline"),
    (((world.inc.get(iid).owner != "") and (dutyGroupOf(world.inc.get(iid).owner) != "")) == true),
  }

  def e_addressee_signed_out_to_group_0(w0: World, c: Ctx, iid: str): World = {
    val group_559 = dutyGroupOf(w0.inc.get(iid).owner)
    val w560 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_559 }) }
    w560
  }

  def e_addressee_signed_out_to_group_1(w0: World, c: Ctx, iid: str): World = {
    val who_561 = ""
    val w562 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_561 }) }
    w562
  }

  def e_addressee_signed_out_to_group_2(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_signed_out_to_group_3(w0: World, c: Ctx, iid: str): World = {
    val whom_563 = addressee(w0.inc.get(iid))
    val w564 = if (((whom_563 != "") and (whom_563 != c.actor))) w0 else w0
    w564
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
    val who_565 = ""
    val w566 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_565 }) }
    w566
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
    val who_567 = ""
    val w568 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_567 }) }
    w568
  }

  def e_owner_signed_out_1(w0: World, c: Ctx, iid: str): World = {
    val w569 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w569
  }

  def e_owner_signed_out_2(w0: World, c: Ctx, iid: str): World = {
    val w570 = if (timerDef("hold").startsOnce) {
      val w571 = ec_pauseTimer(w0, c, iid, "hold")
      w571
    } else {
      val keep_572 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w573 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_572) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w574 = { ...w573, inc: w573.inc.set(iid, { ...w573.inc.get(iid), timers: w573.inc.get(iid).timers.set("hold", { ...w573.inc.get(iid).timers.get("hold"), paused: keep_572 }) }) }
      val w575 = { ...w574, inc: w574.inc.set(iid, { ...w574.inc.get(iid), timers: w574.inc.get(iid).timers.set("hold", { ...w574.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w576 = { ...w575, inc: w575.inc.set(iid, { ...w575.inc.get(iid), timers: w575.inc.get(iid).timers.set("hold", { ...w575.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w576
    }
    w570
  }

  def e_owner_signed_out_3(w0: World, c: Ctx, iid: str): World = {
    val w577 = if (not(timerDef("resolution").pausable)) {
      val w578 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w579 = { ...w578, inc: w578.inc.set(iid, { ...w578.inc.get(iid), timers: w578.inc.get(iid).timers.set("resolution", { ...w578.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w579
    } else {
      val w580 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w581 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w582 = { ...w581, inc: w581.inc.set(iid, { ...w581.inc.get(iid), timers: w581.inc.get(iid).timers.set("resolution", { ...w581.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w583 = { ...w582, inc: w582.inc.set(iid, { ...w582.inc.get(iid), timers: w582.inc.get(iid).timers.set("resolution", { ...w582.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w583
    } else w0
      w580
    }
    w577
  }

  def e_owner_signed_out_4(w0: World, c: Ctx, iid: str): World = {
    val w584 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w585 = if (timerDef("reaction").startsOnce) {
      val w586 = ec_resumeTimer(w0, c, iid, "reaction")
      w586
    } else {
      val w587 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w588 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w589 = { ...w588, inc: w588.inc.set(iid, { ...w588.inc.get(iid), timers: w588.inc.get(iid).timers.set("reaction", { ...w588.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w590 = { ...w589, inc: w589.inc.set(iid, { ...w589.inc.get(iid), timers: w589.inc.get(iid).timers.set("reaction", { ...w589.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w590
    } else {
      val sec_591 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w592 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_591 < 0)) 0 else (c.now + (sec_591 * 1000))) }) }) }
      val w593 = { ...w592, inc: w592.inc.set(iid, { ...w592.inc.get(iid), timers: w592.inc.get(iid).timers.set("reaction", { ...w592.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w594 = { ...w593, inc: w593.inc.set(iid, { ...w593.inc.get(iid), timers: w593.inc.get(iid).timers.set("reaction", { ...w593.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w595 = { ...w594, inc: w594.inc.set(iid, { ...w594.inc.get(iid), timers: w594.inc.get(iid).timers.set("reaction", { ...w594.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w595
    }
      w587
    }
      w585
    }
    w584
  }

  def e_owner_signed_out_5(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_owner_signed_out_6(w0: World, c: Ctx, iid: str): World = {

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
    val w7 = e_owner_signed_out_6(w6, c1, iid)
    w7
  }

  // addressee_lost_access: system → new

  def ok_addressee_lost_access(c: Ctx, iid: str): bool = all {
    Set("pending_acceptance", "in_progress", "on_hold").contains(world.inc.get(iid).state),
    ((addressee(world.inc.get(iid)) != "") and (hasAccess(addressee(world.inc.get(iid)), world.inc.get(iid)) == false)),
  }

  def e_addressee_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val who_596 = ""
    val w597 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_596 }) }
    w597
  }

  def e_addressee_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val group_598 = ""
    val w599 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_598 }) }
    w599
  }

  def e_addressee_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w600 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w600
  }

  def e_addressee_lost_access_3(w0: World, c: Ctx, iid: str): World = {
    val w601 = if (timerDef("hold").startsOnce) {
      val w602 = ec_pauseTimer(w0, c, iid, "hold")
      w602
    } else {
      val keep_603 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w604 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_603) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w605 = { ...w604, inc: w604.inc.set(iid, { ...w604.inc.get(iid), timers: w604.inc.get(iid).timers.set("hold", { ...w604.inc.get(iid).timers.get("hold"), paused: keep_603 }) }) }
      val w606 = { ...w605, inc: w605.inc.set(iid, { ...w605.inc.get(iid), timers: w605.inc.get(iid).timers.set("hold", { ...w605.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w607 = { ...w606, inc: w606.inc.set(iid, { ...w606.inc.get(iid), timers: w606.inc.get(iid).timers.set("hold", { ...w606.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w607
    }
    w601
  }

  def e_addressee_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val w608 = if (not(timerDef("resolution").pausable)) {
      val w609 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w610 = { ...w609, inc: w609.inc.set(iid, { ...w609.inc.get(iid), timers: w609.inc.get(iid).timers.set("resolution", { ...w609.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w610
    } else {
      val w611 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w612 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w613 = { ...w612, inc: w612.inc.set(iid, { ...w612.inc.get(iid), timers: w612.inc.get(iid).timers.set("resolution", { ...w612.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w614 = { ...w613, inc: w613.inc.set(iid, { ...w613.inc.get(iid), timers: w613.inc.get(iid).timers.set("resolution", { ...w613.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w614
    } else w0
      w611
    }
    w608
  }

  def e_addressee_lost_access_5(w0: World, c: Ctx, iid: str): World = {
    val w615 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w616 = if (timerDef("reaction").startsOnce) {
      val w617 = ec_resumeTimer(w0, c, iid, "reaction")
      w617
    } else {
      val w618 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w619 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w620 = { ...w619, inc: w619.inc.set(iid, { ...w619.inc.get(iid), timers: w619.inc.get(iid).timers.set("reaction", { ...w619.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w621 = { ...w620, inc: w620.inc.set(iid, { ...w620.inc.get(iid), timers: w620.inc.get(iid).timers.set("reaction", { ...w620.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w621
    } else {
      val sec_622 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w623 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_622 < 0)) 0 else (c.now + (sec_622 * 1000))) }) }) }
      val w624 = { ...w623, inc: w623.inc.set(iid, { ...w623.inc.get(iid), timers: w623.inc.get(iid).timers.set("reaction", { ...w623.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w625 = { ...w624, inc: w624.inc.set(iid, { ...w624.inc.get(iid), timers: w624.inc.get(iid).timers.set("reaction", { ...w624.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w626 = { ...w625, inc: w625.inc.set(iid, { ...w625.inc.get(iid), timers: w625.inc.get(iid).timers.set("reaction", { ...w625.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w626
    }
      w618
    }
      w616
    }
    w615
  }

  def e_addressee_lost_access_6(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_7(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_lost_access_8(w0: World, c: Ctx, iid: str): World = {
    val whom_627 = settings.alerts.target
    val w628 = if (((whom_627 != "") and (whom_627 != c.actor))) w0 else w0
    w628
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
    val who_629 = ""
    val w630 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_629 }) }
    w630
  }

  def e_addressee_cannot_accept_1(w0: World, c: Ctx, iid: str): World = {
    val group_631 = ""
    val w632 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_631 }) }
    w632
  }

  def e_addressee_cannot_accept_2(w0: World, c: Ctx, iid: str): World = {
    val w633 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w634 = if (timerDef("reaction").startsOnce) {
      val w635 = ec_resumeTimer(w0, c, iid, "reaction")
      w635
    } else {
      val w636 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w637 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w638 = { ...w637, inc: w637.inc.set(iid, { ...w637.inc.get(iid), timers: w637.inc.get(iid).timers.set("reaction", { ...w637.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w639 = { ...w638, inc: w638.inc.set(iid, { ...w638.inc.get(iid), timers: w638.inc.get(iid).timers.set("reaction", { ...w638.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w639
    } else {
      val sec_640 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w641 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_640 < 0)) 0 else (c.now + (sec_640 * 1000))) }) }) }
      val w642 = { ...w641, inc: w641.inc.set(iid, { ...w641.inc.get(iid), timers: w641.inc.get(iid).timers.set("reaction", { ...w641.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w643 = { ...w642, inc: w642.inc.set(iid, { ...w642.inc.get(iid), timers: w642.inc.get(iid).timers.set("reaction", { ...w642.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w644 = { ...w643, inc: w643.inc.set(iid, { ...w643.inc.get(iid), timers: w643.inc.get(iid).timers.set("reaction", { ...w643.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w644
    }
      w636
    }
      w634
    }
    w633
  }

  def e_addressee_cannot_accept_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_4(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_addressee_cannot_accept_5(w0: World, c: Ctx, iid: str): World = {
    val whom_645 = settings.alerts.target
    val w646 = if (((whom_645 != "") and (whom_645 != c.actor))) w0 else w0
    w646
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
    not(settings.session.states.foldl(false, (acc, s_647) => acc or ((s_647.id == agentState(c.me)) and s_647.readOnly))),
    ((world.inc.get(iid).owner == c.me) or unowned(world.inc.get(iid))),
    { val ps_648 = incidentById(incs(world), c.form.primaryId)  ((((ps_648.length() > 0) and (ps_648[0].id != world.inc.get(iid).id)) and (ps_648[0].linkedTo == "")) and ((ps_648[0].state == "new") or ((ps_648[0].state == "in_progress") and (ps_648[0].owner == c.me)))) },
    { val ps_649 = incidentById(incs(world), c.form.primaryId)  ((ps_649.length() > 0) and (ps_649[0].scenario == world.inc.get(iid).scenario)) },
  }

  def e_merge_0(w0: World, c: Ctx, iid: str): World = {
    val w650 = shareAnswers(w0, w0.inc.get(iid).id, c.form.primaryId)
    w650
  }

  def e_merge_1(w0: World, c: Ctx, iid: str): World = {
    val ps_651 = incidentById(incs(w0), c.form.primaryId)
    val w652 = if ((ps_651.length() > 0)) {
      val w653 = linkedOf(incs(w0), w0.inc.get(iid).id).select(e_660 => not(isDone(e_660))).foldl([], (acc, x656) => acc.append(x656.id)).foldl(w0, (wf654, cId655) => {
      val w657 = { ...wf654, inc: wf654.inc.set(cId655, { ...wf654.inc.get(cId655), leftGroup: { primaryId: wf654.inc.get(cId655).linkedTo, linkedAt: wf654.inc.get(cId655).linkedAt, at: c.now } }) }
      val w658 = { ...w657, inc: w657.inc.set(cId655, { ...w657.inc.get(cId655), linkedTo: ps_651[0].id }) }
      val w659 = { ...w658, inc: w658.inc.set(cId655, { ...w658.inc.get(cId655), linkedAt: c.now }) }
      w659
    })
      w653
    } else w0
    w652
  }

  def e_merge_2(w0: World, c: Ctx, iid: str): World = {
    val primary_661 = c.form.primaryId
    val w662 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: primary_661 }) }
    val w663 = { ...w662, inc: w662.inc.set(iid, { ...w662.inc.get(iid), linkedAt: c.now }) }
    w663
  }

  def e_merge_3(w0: World, c: Ctx, iid: str): World = {
    val who_664 = ""
    val w665 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), owner: who_664 }) }
    w665
  }

  def e_merge_4(w0: World, c: Ctx, iid: str): World = {
    val group_666 = ""
    val w667 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), assignmentGroup: group_666 }) }
    w667
  }

  def e_merge_5(w0: World, c: Ctx, iid: str): World = {
    val w668 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), holdReasonId: "" }) }
    w668
  }

  def e_merge_6(w0: World, c: Ctx, iid: str): World = {
    val w669 = if (timerDef("reaction").startsOnce) {
      val w670 = ec_pauseTimer(w0, c, iid, "reaction")
      w670
    } else {
      val keep_671 = (((timerDef("reaction").keepsLeft and (w0.inc.get(iid).timers.get("reaction").due != 0)) and (w0.inc.get(iid).timers.get("reaction").fired != w0.inc.get(iid).timers.get("reaction").due)) and (w0.inc.get(iid).timers.get("reaction").due > c.now))
      val w672 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), left: (if (keep_671) (w0.inc.get(iid).timers.get("reaction").due - c.now) else 0) }) }) }
      val w673 = { ...w672, inc: w672.inc.set(iid, { ...w672.inc.get(iid), timers: w672.inc.get(iid).timers.set("reaction", { ...w672.inc.get(iid).timers.get("reaction"), paused: keep_671 }) }) }
      val w674 = { ...w673, inc: w673.inc.set(iid, { ...w673.inc.get(iid), timers: w673.inc.get(iid).timers.set("reaction", { ...w673.inc.get(iid).timers.get("reaction"), due: 0 }) }) }
      val w675 = { ...w674, inc: w674.inc.set(iid, { ...w674.inc.get(iid), timers: w674.inc.get(iid).timers.set("reaction", { ...w674.inc.get(iid).timers.get("reaction"), since: 0 }) }) }
      w675
    }
    w669
  }

  def e_merge_7(w0: World, c: Ctx, iid: str): World = {
    val w676 = if (not(timerDef("resolution").pausable)) {
      val w677 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w678 = { ...w677, inc: w677.inc.set(iid, { ...w677.inc.get(iid), timers: w677.inc.get(iid).timers.set("resolution", { ...w677.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w678
    } else {
      val w679 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w680 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w681 = { ...w680, inc: w680.inc.set(iid, { ...w680.inc.get(iid), timers: w680.inc.get(iid).timers.set("resolution", { ...w680.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w682 = { ...w681, inc: w681.inc.set(iid, { ...w681.inc.get(iid), timers: w681.inc.get(iid).timers.set("resolution", { ...w681.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w682
    } else w0
      w679
    }
    w676
  }

  def e_merge_8(w0: World, c: Ctx, iid: str): World = {
    val ps_683 = incidentById(incs(w0), c.form.primaryId)
    val w684 = if (((((ps_683.length() > 0) and (leftOf(w0.inc.get(iid), "resolution", c.now) >= 0)) and not(spent(w0.inc.get(iid), "resolution", c.now))) and not(spent(ps_683[0], "resolution", c.now)))) {
      val t_685 = ps_683[0].timers.get("resolution")
      val left_686 = leftOf(w0.inc.get(iid), "resolution", c.now)
      val was_687 = (if ((t_685.due != 0)) (t_685.due - c.now) else (if (t_685.paused) t_685.left else (timerSec(ps_683[0], "resolution", "") * 1000)))
      val w688 = if ((left_686 < was_687)) {
      val w689 = ps_683.foldl([], (acc, x692) => acc.append(x692.id)).foldl(w0, (wf690, pId691) => {
      val w693 = if ((t_685.due != 0)) {
      val w694 = { ...wf690, inc: wf690.inc.set(pId691, { ...wf690.inc.get(pId691), timers: wf690.inc.get(pId691).timers.set("resolution", { ...wf690.inc.get(pId691).timers.get("resolution"), due: (c.now + left_686) }) }) }
      w694
    } else {
      val w695 = { ...wf690, inc: wf690.inc.set(pId691, { ...wf690.inc.get(pId691), timers: wf690.inc.get(pId691).timers.set("resolution", { ...wf690.inc.get(pId691).timers.get("resolution"), left: left_686 }) }) }
      val w696 = { ...w695, inc: w695.inc.set(pId691, { ...w695.inc.get(pId691), timers: w695.inc.get(pId691).timers.set("resolution", { ...w695.inc.get(pId691).timers.get("resolution"), paused: true }) }) }
      w696
    }
      w693
    })
      w689
    } else w0
      w688
    } else w0
    w684
  }

  def e_merge_9(w0: World, c: Ctx, iid: str): World = {
    val w697 = if (timerDef("hold").startsOnce) {
      val w698 = ec_pauseTimer(w0, c, iid, "hold")
      w698
    } else {
      val keep_699 = (((timerDef("hold").keepsLeft and (w0.inc.get(iid).timers.get("hold").due != 0)) and (w0.inc.get(iid).timers.get("hold").fired != w0.inc.get(iid).timers.get("hold").due)) and (w0.inc.get(iid).timers.get("hold").due > c.now))
      val w700 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("hold", { ...w0.inc.get(iid).timers.get("hold"), left: (if (keep_699) (w0.inc.get(iid).timers.get("hold").due - c.now) else 0) }) }) }
      val w701 = { ...w700, inc: w700.inc.set(iid, { ...w700.inc.get(iid), timers: w700.inc.get(iid).timers.set("hold", { ...w700.inc.get(iid).timers.get("hold"), paused: keep_699 }) }) }
      val w702 = { ...w701, inc: w701.inc.set(iid, { ...w701.inc.get(iid), timers: w701.inc.get(iid).timers.set("hold", { ...w701.inc.get(iid).timers.get("hold"), due: 0 }) }) }
      val w703 = { ...w702, inc: w702.inc.set(iid, { ...w702.inc.get(iid), timers: w702.inc.get(iid).timers.set("hold", { ...w702.inc.get(iid).timers.get("hold"), since: 0 }) }) }
      w703
    }
    w697
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
    not(settings.session.states.foldl(false, (acc, s_704) => acc or ((s_704.id == agentState(c.me)) and s_704.readOnly))),
    { val ps_705 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_705.length() > 0) and ((ownership(c.me, ps_705[0]) == "owner") or unowned(ps_705[0]))) },
  }

  def e_detach_0(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_detach_1(w0: World, c: Ctx, iid: str): World = {
    val ps_706 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w707 = if (((ps_706.length() > 0) and (leftOf(ps_706[0], "resolution", c.now) >= 0))) {
      val w708 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w709 = { ...w708, inc: w708.inc.set(iid, { ...w708.inc.get(iid), timers: w708.inc.get(iid).timers.set("resolution", { ...w708.inc.get(iid).timers.get("resolution"), left: leftOf(ps_706[0], "resolution", c.now) }) }) }
      val w710 = { ...w709, inc: w709.inc.set(iid, { ...w709.inc.get(iid), timers: w709.inc.get(iid).timers.set("resolution", { ...w709.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w711 = if ((leftOf(ps_706[0], "resolution", c.now) == 0)) {
      val w712 = { ...w710, inc: w710.inc.set(iid, { ...w710.inc.get(iid), timers: w710.inc.get(iid).timers.set("resolution", { ...w710.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_706[0], "resolution", c.now)) ps_706[0].timers.get("resolution").fired else ps_706[0].timers.get("resolution").due) }) }) }
      w712
    } else w710
      w711
    } else w0
    w707
  }

  def e_detach_2(w0: World, c: Ctx, iid: str): World = {
    val w713 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_714 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w715 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w716 = { ...w715, inc: w715.inc.set(iid, { ...w715.inc.get(iid), linkedTo: "" }) }
      val w717 = { ...w716, inc: w716.inc.set(iid, { ...w716.inc.get(iid), linkedAt: 0 }) }
      val w718 = if (((ps_714.length() > 0) and ("" != ""))) w717 else w717
      val w719 = if (("" != "")) {
      val w720 = ps_714.foldl([], (acc, x723) => acc.append(x723.id)).foldl(w718, (wf721, pId722) => wf721)
      w720
    } else w718
      w719
    } else {
      val w724 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w725 = { ...w724, inc: w724.inc.set(iid, { ...w724.inc.get(iid), linkedAt: 0 }) }
      w725
    }
    w713
  }

  def e_detach_3(w0: World, c: Ctx, iid: str): World = {
    val w726 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w727 = if (timerDef("reaction").startsOnce) {
      val w728 = ec_resumeTimer(w0, c, iid, "reaction")
      w728
    } else {
      val w729 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w730 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w731 = { ...w730, inc: w730.inc.set(iid, { ...w730.inc.get(iid), timers: w730.inc.get(iid).timers.set("reaction", { ...w730.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w732 = { ...w731, inc: w731.inc.set(iid, { ...w731.inc.get(iid), timers: w731.inc.get(iid).timers.set("reaction", { ...w731.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w732
    } else {
      val sec_733 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w734 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_733 < 0)) 0 else (c.now + (sec_733 * 1000))) }) }) }
      val w735 = { ...w734, inc: w734.inc.set(iid, { ...w734.inc.get(iid), timers: w734.inc.get(iid).timers.set("reaction", { ...w734.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w736 = { ...w735, inc: w735.inc.set(iid, { ...w735.inc.get(iid), timers: w735.inc.get(iid).timers.set("reaction", { ...w735.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w737 = { ...w736, inc: w736.inc.set(iid, { ...w736.inc.get(iid), timers: w736.inc.get(iid).timers.set("reaction", { ...w736.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w737
    }
      w729
    }
      w727
    }
    w726
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
    { val ps_738 = incidentById(incs(world), world.inc.get(iid).linkedTo)  ((ps_738.length() > 0) and isDone(ps_738[0])) },
  }

  def e_close_linked_0(w0: World, c: Ctx, iid: str): World = {
    val ps_739 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w740 = if ((ps_739.length() > 0)) {
      val w741 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closeResultId: ps_739[0].closeResultId }) }
      val w742 = { ...w741, inc: w741.inc.set(iid, { ...w741.inc.get(iid), closeCauseId: ps_739[0].closeCauseId }) }
      val w743 = { ...w742, inc: w742.inc.set(iid, { ...w742.inc.get(iid), result: ps_739[0].result }) }
      val w744 = { ...w743, inc: w743.inc.set(iid, { ...w743.inc.get(iid), closedBy: ps_739[0].closedBy }) }
      val w745 = { ...w744, inc: w744.inc.set(iid, { ...w744.inc.get(iid), owner: ps_739[0].closedBy }) }
      w745
    } else w0
    w740
  }

  def e_close_linked_1(w0: World, c: Ctx, iid: str): World = {
    val w746 = if (not(timerDef("resolution").pausable)) {
      val w747 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w748 = { ...w747, inc: w747.inc.set(iid, { ...w747.inc.get(iid), timers: w747.inc.get(iid).timers.set("resolution", { ...w747.inc.get(iid).timers.get("resolution"), since: 0 }) }) }
      w748
    } else {
      val w749 = if ((w0.inc.get(iid).timers.get("resolution").due != 0)) {
      val w750 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), left: (if (((w0.inc.get(iid).timers.get("resolution").due - c.now) > 0)) (w0.inc.get(iid).timers.get("resolution").due - c.now) else 0) }) }) }
      val w751 = { ...w750, inc: w750.inc.set(iid, { ...w750.inc.get(iid), timers: w750.inc.get(iid).timers.set("resolution", { ...w750.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w752 = { ...w751, inc: w751.inc.set(iid, { ...w751.inc.get(iid), timers: w751.inc.get(iid).timers.set("resolution", { ...w751.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      w752
    } else w0
      w749
    }
    w746
  }

  def e_close_linked_2(w0: World, c: Ctx, iid: str): World = {
    val value_753 = c.now
    val w754 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), closedAt: value_753 }) }
    w754
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
    { val ps_755 = incidentById(incs(world), world.inc.get(iid).linkedTo)  { val who_756 = (if (((ps_755.length() > 0) and not(isDone(ps_755[0])))) addressee(ps_755[0]) else "")  ((who_756 != "") and (hasAccess(who_756, world.inc.get(iid)) == false)) } },
  }

  def e_linked_lost_access_0(w0: World, c: Ctx, iid: str): World = {
    val ps_757 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
    val w758 = if (((ps_757.length() > 0) and (leftOf(ps_757[0], "resolution", c.now) >= 0))) {
      val w759 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("resolution", { ...w0.inc.get(iid).timers.get("resolution"), due: 0 }) }) }
      val w760 = { ...w759, inc: w759.inc.set(iid, { ...w759.inc.get(iid), timers: w759.inc.get(iid).timers.set("resolution", { ...w759.inc.get(iid).timers.get("resolution"), left: leftOf(ps_757[0], "resolution", c.now) }) }) }
      val w761 = { ...w760, inc: w760.inc.set(iid, { ...w760.inc.get(iid), timers: w760.inc.get(iid).timers.set("resolution", { ...w760.inc.get(iid).timers.get("resolution"), paused: true }) }) }
      val w762 = if ((leftOf(ps_757[0], "resolution", c.now) == 0)) {
      val w763 = { ...w761, inc: w761.inc.set(iid, { ...w761.inc.get(iid), timers: w761.inc.get(iid).timers.set("resolution", { ...w761.inc.get(iid).timers.get("resolution"), fired: (if (spent(ps_757[0], "resolution", c.now)) ps_757[0].timers.get("resolution").fired else ps_757[0].timers.get("resolution").due) }) }) }
      w763
    } else w761
      w762
    } else w0
    w758
  }

  def e_linked_lost_access_1(w0: World, c: Ctx, iid: str): World = {
    val w764 = if ((w0.inc.get(iid).linkedTo != "")) {
      val ps_765 = incidentById(incs(w0), w0.inc.get(iid).linkedTo)
      val w766 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), leftGroup: { primaryId: w0.inc.get(iid).linkedTo, linkedAt: w0.inc.get(iid).linkedAt, at: c.now } }) }
      val w767 = { ...w766, inc: w766.inc.set(iid, { ...w766.inc.get(iid), linkedTo: "" }) }
      val w768 = { ...w767, inc: w767.inc.set(iid, { ...w767.inc.get(iid), linkedAt: 0 }) }
      val w769 = if (((ps_765.length() > 0) and ("workflow.journal.linked_lost_access" != ""))) w768 else w768
      val w770 = if (("workflow.journal.linked_lost_access_primary" != "")) {
      val w771 = ps_765.foldl([], (acc, x774) => acc.append(x774.id)).foldl(w769, (wf772, pId773) => wf772)
      w771
    } else w769
      w770
    } else {
      val w775 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), linkedTo: "" }) }
      val w776 = { ...w775, inc: w775.inc.set(iid, { ...w775.inc.get(iid), linkedAt: 0 }) }
      w776
    }
    w764
  }

  def e_linked_lost_access_2(w0: World, c: Ctx, iid: str): World = {
    val w777 = if ((false and (w0.inc.get(iid).timers.get("reaction").due != 0))) w0 else {
      val w778 = if (timerDef("reaction").startsOnce) {
      val w779 = ec_resumeTimer(w0, c, iid, "reaction")
      w779
    } else {
      val w780 = if ((("" == "continue") and w0.inc.get(iid).timers.get("reaction").paused)) {
      val w781 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (c.now + w0.inc.get(iid).timers.get("reaction").left) }) }) }
      val w782 = { ...w781, inc: w781.inc.set(iid, { ...w781.inc.get(iid), timers: w781.inc.get(iid).timers.set("reaction", { ...w781.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w783 = { ...w782, inc: w782.inc.set(iid, { ...w782.inc.get(iid), timers: w782.inc.get(iid).timers.set("reaction", { ...w782.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w783
    } else {
      val sec_784 = timerSec(w0.inc.get(iid), "reaction", (if (("" == "continue")) "" else ""))
      val w785 = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), timers: w0.inc.get(iid).timers.set("reaction", { ...w0.inc.get(iid).timers.get("reaction"), due: (if ((sec_784 < 0)) 0 else (c.now + (sec_784 * 1000))) }) }) }
      val w786 = { ...w785, inc: w785.inc.set(iid, { ...w785.inc.get(iid), timers: w785.inc.get(iid).timers.set("reaction", { ...w785.inc.get(iid).timers.get("reaction"), since: c.now }) }) }
      val w787 = { ...w786, inc: w786.inc.set(iid, { ...w786.inc.get(iid), timers: w786.inc.get(iid).timers.set("reaction", { ...w786.inc.get(iid).timers.get("reaction"), paused: false }) }) }
      val w788 = { ...w787, inc: w787.inc.set(iid, { ...w787.inc.get(iid), timers: w787.inc.get(iid).timers.set("reaction", { ...w787.inc.get(iid).timers.get("reaction"), left: 0 }) }) }
      w788
    }
      w780
    }
      w778
    }
    w777
  }

  def e_linked_lost_access_3(w0: World, c: Ctx, iid: str): World = {

    w0
  }

  def e_linked_lost_access_4(w0: World, c: Ctx, iid: str): World = {
    val whom_789 = settings.alerts.target
    val w790 = if (((whom_789 != "") and (whom_789 != c.actor))) w0 else w0
    w790
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
      settings.holdReasons.foldl(false, (acc, r_791) => acc or ((r_791.id == c.form.reasonId) and (r_791.setBy != "system"))),
    },
  }

  def form_transfer(c: Ctx, iid: str): bool = all {
    c.form.targetId == "" or all {
      TARGETS.contains(c.form.targetId),
      ((not(isSelf(c.me, c.form.targetId)) and (c.form.targetId != addressee(world.inc.get(iid)))) and canAccept(c.form.targetId, world.inc.get(iid), "")),
      linkedOf(incs(world), world.inc.get(iid).id).foldl(true, (acc, e_792) => acc and (isDone(e_792) or hasAccess(c.form.targetId, e_792))),
    },
  }

  def form_close(c: Ctx, iid: str): bool = all {
    c.form.resultId == "" or all {
      Set("processed", "false_alarm", "duplicate", "drill", "impossible", "mass").contains(c.form.resultId),
      closeOptions(c.me, world.inc.get(iid), c.surface).foldl(false, (acc, i_793) => acc or (i_793.id == c.form.resultId)),
      settings.closeResults.foldl(false, (acc, i_794) => acc or ((i_794.id == c.form.resultId) and stepsOk(i_794, world.inc.get(iid)))),
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
    else if (tid == "system_hold_break") ok_system_hold_break(c, iid)
    else if (tid == "system_hold_idle") ok_system_hold_idle(c, iid)
    else if (tid == "system_release_idle") ok_system_release_idle(c, iid)
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
    else if (tid == "system_hold_break") apply_system_hold_break(c, iid, w)
    else if (tid == "system_hold_idle") apply_system_hold_idle(c, iid, w)
    else if (tid == "system_release_idle") apply_system_release_idle(c, iid, w)
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
    { id: "system_hold_break", trigger: "system", actor: "system", from: Set("in_progress"), timer: "", idleSec: 0, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "system_hold_idle", trigger: "system", actor: "system", from: Set("in_progress"), timer: "", idleSec: MACHINE_SETTINGS.session.idleHoldSec, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
    { id: "system_release_idle", trigger: "system", actor: "system", from: Set("on_hold"), timer: "", idleSec: MACHINE_SETTINGS.session.idleReleaseSec, ownedByAgent: true, surfaces: Set(), bulkOnly: false },
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
  val reached_system_hold_break = lastAction.name == "system_hold_break"
  val reached_system_hold_idle = lastAction.name == "system_hold_idle"
  val reached_system_release_idle = lastAction.name == "system_release_idle"
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
    ["in_progress"].foldl(false, (acc, y795) => acc or y795 == world.inc.get(iid).state),
    (world.inc.get(iid).owner == c.me),
    not(settings.session.states.foldl(false, (acc, s_796) => acc or ((s_796.id == agentState(c.me)) and s_796.readOnly))),
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
  pure val GROUP = "g"
  pure val GROUPS: Set[str] = Set(GROUP)
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

  /* ===== Факты мира (cel.world машины) ===== */

  def can(who: str, perm: str): bool = OPERATORS.contains(who) and cfg.perms.get(who).contains(perm)
  def access(who: str, x: Incident): bool = OPERATORS.contains(who) and cfg.access.get(who).contains(x.id)
  def isOperator(id: str): bool = OPERATORS.contains(id)
  def isGroup(id: str): bool = GROUPS.contains(id)
  def members(g: str): List[str] = if (isGroup(g)) OPERATOR_LIST.select(m => cfg.members.get(g).contains(m)) else []
  def dutyGroups: List[str] = [GROUP]
  // Кому вообще можно передавать: люди и дежурная группа (§8.1, BUG-85)
  def transferTargets: List[str] = OPERATOR_LIST.concat([GROUP])
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
      autoRun' = autoRun,
    }
  }

  action agent(a: str, name: str, state: str, beat: bool): bool = all {
    agents' = agents.set(a, state),
    lastBeat' = if (beat) lastBeat.set(a, clock) else lastBeat,
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
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
    autoRun' = INCIDENTS.mapBy(j => 0),
  }
  action restoreLink(a: str): bool = all {
    not(link.get(a)),
    link' = link.set(a, true),
    lastBeat' = lastBeat.set(a, clock),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, changedAt' = changedAt,
    lastAction' = act0("env", "restore_link", a, NOBODY),
    autoRun' = INCIDENTS.mapBy(j => 0),
  }

  // Запрос оператора, который ничего не изменил, — отказанный переход, подсчёт выборки: тоже признак активности.
  // Любой запрос, кроме чтения (§12.3, BUG-76 а), RULE-112); нужна связь
  action request(a: str): bool = all {
    link.get(a),
    lastBeat' = lastBeat.set(a, clock),
    world' = world, cfg' = cfg, settings' = settings, clock' = clock, agents' = agents, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", "request", a, NOBODY),
    autoRun' = INCIDENTS.mapBy(j => 0),
  }

  // Сменились роли (§5): доступ к объекту инцидента, право «Принимать»
  action roles(a: str, name: str, c: Config): bool = all {
    cfg' = c,
    world' = world, settings' = settings, clock' = clock, agents' = agents, lastBeat' = lastBeat, link' = link, changedAt' = changedAt,
    lastAction' = act0("env", name, a, NOBODY),
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

  /* ===== Начало и шаг ===== */

  action init = {
    nondet perms = OPERATORS.setOfMaps(USED_PERMISSIONS.powerset()).oneOf()
    nondet access = OPERATORS.setOfMaps(INCIDENTS.powerset()).oneOf()
    nondet grp = OPERATORS.powerset().oneOf()
    // Настройки, от которых зависят ветки автоматических переходов, — из машины (BRANCH_SETTINGS, PROC-43)
    nondet branch = BRANCH_SETTINGS.oneOf()
    nondet maxActive = Set(0, 1).oneOf()
    nondet maxOnHold = Set(0, 1).oneOf()
    nondet level1 = OPERATORS.oneOf()
    nondet starts = OPERATORS.setOfMaps(AGENT_STARTS).oneOf()
    val levels = MACHINE_SETTINGS.escalation.levels
    all {
      cfg' = { perms: perms, access: access, members: Map(GROUP -> grp) },
      // Настройки — значения машины; перебираются ветки автоматики (withBranches) и лимиты, люди — люди модели:
      // уровень 1 — человек, уровень 2 — дежурная группа, алерты — группе
      settings' = withBranches({ ...MACHINE_SETTINGS,
        escalation: { ...MACHINE_SETTINGS.escalation,
          levels: [{ ...levels[0], targetKind: "user", target: level1 }, { ...levels[1], targetKind: "group", target: GROUP }] },
        alerts: { ...MACHINE_SETTINGS.alerts, targetKind: "group", target: GROUP },
        limits: { ...MACHINE_SETTINGS.limits, maxActive: maxActive, maxOnHold: maxOnHold },
      }, branch),
      world' = { inc: INCIDENTS.mapBy(i => NO_INCIDENT), answers: INCIDENTS.mapBy(i => Set()) },
      clock' = START,
      // Оператор — ещё не вошёл (начальное машины) или уже вошёл (RULE-99)
      agents' = starts,
      lastBeat' = OPERATORS.mapBy(a => START),
      link' = OPERATORS.mapBy(a => true),
      changedAt' = INCIDENTS.mapBy(i => 0),
      lastAction' = act0("init", "init", NOBODY, NOBODY),
      autoRun' = INCIDENTS.mapBy(i => 0),
    }
  }

  pure val MANUAL_IDS: Set[str] = ofTrigger("manual").foldl(Set(), (s, t) => if (t.bulkOnly) s else s.union(Set(t.id)))
  action step = {
    val pending = INCIDENTS.filter(i => nextAuto(i).length() > 0)
    if (pending.size() > 0) {
      nondet j = pending.oneOf()
      fire(j)
    } else stepFree
  }
  action stepFree = {
    nondet i = INCIDENTS.oneOf()
    nondet a = OPERATORS.oneOf()
    any {
      {
        nondet sc = SCENARIOS.oneOf()
        nondet prio = PRIORITIES.oneOf()
        create(i, sc, prio)
      },
      {
        nondet tid = MANUAL_IDS.oneOf()
        nondet target = TARGETS.oneOf()
        nondet reason = HOLD_REASONS_BY_OPERATOR.oneOf()
        nondet result = CLOSE_RESULT_IDS.oneOf()
        nondet surface = tr(tid).surfaces.oneOf()
        val form = { ...NO_FORM, targetId: target, reasonId: reason, resultId: result,
          causeId: if (CAUSE_FOR.keys().contains(result)) CAUSE_FOR.get(result) else "", comment: "c" }
        manual(a, tid, i, form, surface)
      },
      {
        nondet sel = INCIDENTS.powerset().oneOf()
        mergeAuto(a, sel)
      },
      time,
      {
        nondet m = AGENT_MOVES.oneOf()
        agentMove(a, m.id)
      },
      loseLink(a),
      restoreLink(a),
      request(a),
      toggleAccess(a, i),
      toggleAccept(a),
      {
        nondet st = STEPS.oneOf()
        answer(a, i, st)
      },
    }
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
  // Сейчас выполнится автоматический переход этого инцидента — системный или по таймеру
  def autoPending(i: str): bool = AUTO.foldl(false, (acc, t) => acc or autoReady(t, i))

  // 1. Владелец по состоянию (§2.1)
  val ownerByState = INCIDENTS.forall(i => {
    val x = incOf(i)
    val s = x.state
    if (s == "new" or s == "linked") x.owner == NOBODY and x.assignmentGroup == NOBODY
    else if (s == "pending_acceptance")
      (OPERATORS.contains(x.owner) and x.assignmentGroup == NOBODY) or (x.owner == NOBODY and x.assignmentGroup == GROUP)
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
      // Срок удержания идёт, только если он у причины есть: у «нет связи» его нет (RULE-116)
      else if (s == "on_hold") (runs(h) iff holdSec(x) >= 0) and not(runs(z)) and z.paused and not(runs(r))
      else if (s == "closed") not(runs(r)) and not(runs(z)) and not(runs(h))
      // Свой норматив закрытия привязанного на паузе: у группы один срок — срок основного (RULE-97)
      else if (s == "linked") not(runs(r)) and not(runs(h)) and not(runs(z))
      else true,
    }
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
    x.state == "pending_acceptance" implies (mayAccept(who, x) or autoPending(i))
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
      OPEN.contains(p.state) or (p.state == "closed" and autoPending(i)),
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
      Set("pending_acceptance", "in_progress", "on_hold").contains(x.state) implies (reach(who, x) or autoPending(i)),
      (x.state == "linked" and p.state != "closed" and pwho != NOBODY) implies (reach(pwho, x) or autoPending(i) or autoPending(x.linkedTo)),
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
      (Set("pending_acceptance", "in_progress", "on_hold").contains(x.state) and agentState(x.owner) == "offline" and OPERATORS.contains(x.owner)) implies autoPending(i),
      (x.state == "in_progress" and agentState(x.owner) == "not_ready") implies autoPending(i),
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
      (x.state == "in_progress" and idle >= settings.session.idleHoldSec) implies autoPending(i),
      (x.state == "on_hold" and x.holdReasonId != NOBODY and not(HOLD_REASONS_BY_OPERATOR.contains(x.holdReasonId)) and idle >= settings.session.idleReleaseSec) implies autoPending(i),
    }
  })

  // 14. П3. Без людей автоматика конечна: подряд, только со временем, у инцидента — не больше AUTO_BOUND
  //     автоматических переходов; эскалация упирается в потолок, круга нет. Самая длинная цепочка — около 8,
  //     например resolution_overdue → system_hold_idle → hold_overdue → system_release_idle → auto_escalate → …
  //     → escalation_ceiling; при пределе 3 модель находит нарушение — у предела есть запас, но не лишний (PROC-45)
  pure val AUTO_BOUND = 10
  val autoBounded = INCIDENTS.forall(i => autoRun.get(i) <= AUTO_BOUND)

  val inv = all {
    ownerByState,
    holdReasonIffOnHold,
    timersByState,
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
  }
}
