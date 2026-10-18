// -*- mode: Bluespec; -*-
/* Машина состояний инцидента МИ — формальная модель на Quint.

   Источник правил — ../workflow.v4.json; смысл условий и эффектов — как в исполнителе
   прототипа (prototype/engine.js). Модель не заменяет машину: она проверяет её правила
   на маленьком мире — 2 инцидента, 2 оператора, 1 дежурная группа — перебором путей.

   Ядро: create, claim, accept, reject, hold, resume, release, transfer, takeover, close,
   reopen и переходы по таймерам. Пока не моделируются: состояние оператора (все ready,
   agentReady выполнено), системные переходы, merge / linked, смена прав и доступа,
   окно manualWinsOverTimer, журнал, уведомления, сценарий, version.

   Время абстрактное. У таймера фаза: Before — дедлайн впереди, Due — наступил и ещё не
   сработал (timerExpired), Fired — сработал (firedTimers прототипа: каждый дедлайн
   срабатывает один раз). Дедлайн наступает действием окружения expire*.
   Без окна manualWinsOverTimer переход по таймеру срочный: пока он возможен, ручные
   действия над этим инцидентом ждут (как при graceSec = 0).

   Запуск: quint typecheck im.qnt; quint run --max-steps=40 im.qnt */
module im {

  /* ===== Типы ===== */

  type State = Absent | New | Pending | InProgress | OnHold | Closed
  type Run = Idle | Running | Paused
  type Phase = Before | Due | Fired
  type Timer = { mode: Run, phase: Phase }
  // recordBreach: вид нарушения и чьё — адресат в момент нарушения
  type Breach = { kind: str, who: str }

  type Incident = {
    state: State,
    owner: str,        // владелец-человек; NOBODY — нет
    group: str,        // группа-адресат (assignment_group); NOBODY — нет
    holdReason: str,
    level: int,        // escalation_level
    closeResult: str,
    closedBy: str,
    reopenOpen: bool,  // не истёк limits.reopenWindowMin
    transfers: int,    // transfer_count
    reaction: Timer,
    resolution: Timer,
    hold: Timer,
    breaches: List[Breach],
  }

  // Права, доступ и настройки выбираются при старте и дальше не меняются.
  // 0 у лимитов — без ограничения (null в машине)
  type Config = {
    perms: str -> Set[str],
    access: str -> Set[str],   // оператор → инциденты, к объектам которых есть доступ
    members: Set[str],         // участники дежурной группы GROUP
    escalationEnabled: bool,
    onResolutionOverdue: str,  // alert | escalate
    maxActive: int,
    maxOnHold: int,
  }

  type Action = { name: str, actor: str, incident: str }
  // Строка справочника reasonCatalogs.close_result
  type CloseResult = { id: str, perm: str, from: Set[State], ownerOnly: Set[State], steps: bool }

  /* ===== Мир ===== */

  pure val NOBODY = ""
  pure val DISPATCHER = "dispatcher"
  pure val INCIDENTS = Set("i1", "i2")
  pure val OPERATORS = Set("a", "b")
  pure val GROUP = "g"
  pure val TARGETS = OPERATORS.union(Set(GROUP))

  pure val PERMS = Set(
    "incident:claim", "incident:accept", "incident:hold", "incident:release",
    "incident:close", "incident:close:unprocessed", "incident:reopen",
    "incident:transfer:own", "incident:transfer:any", "incident:reassign",
  )

  // escalation.levels: уровень 1 — человек, уровень 2 — группа (обе ветки ifPerson / ifGroup)
  pure val LEVELS = [{ level: 1, target: "b" }, { level: 2, target: GROUP }]
  pure val MAX_LEVEL = 2

  // reasonCatalogs.hold, setBy: operator
  pure val HOLD_REASONS = Set("third_party", "patrol", "no_data")

  // reasonCatalogs.close_result
  pure val CLOSE_RESULTS = Set(
    { id: "processed", perm: "incident:close", from: Set(InProgress), ownerOnly: Set(InProgress), steps: true },
    { id: "false_alarm", perm: "incident:close", from: Set(InProgress), ownerOnly: Set(InProgress), steps: false },
    { id: "duplicate", perm: "incident:close", from: Set(InProgress), ownerOnly: Set(InProgress), steps: false },
    { id: "drill", perm: "incident:close", from: Set(InProgress), ownerOnly: Set(InProgress), steps: false },
    { id: "impossible", perm: "incident:close", from: Set(InProgress), ownerOnly: Set(InProgress), steps: false },
    { id: "mass", perm: "incident:close:unprocessed", from: Set(New, Pending, InProgress, OnHold), ownerOnly: Set(InProgress, OnHold), steps: false },
  )

  pure val IDLE: Timer = { mode: Idle, phase: Before }
  pure val ABSENT: Incident = {
    state: Absent, owner: NOBODY, group: NOBODY, holdReason: NOBODY, level: 0,
    closeResult: NOBODY, closedBy: NOBODY, reopenOpen: false, transfers: 0,
    reaction: IDLE, resolution: IDLE, hold: IDLE, breaches: [],
  }

  /* ===== Состояние ===== */

  var cfg: Config
  var inc: str -> Incident
  var lastAction: Action

  /* ===== Таймеры (§4, §14.8) ===== */

  // startTimer / stopTimer у таймеров без паузы (reaction, hold)
  pure def startT(t: Timer): Timer = { mode: Running, phase: Before }
  pure def stopT(t: Timer): Timer = IDLE
  // startTimer … ifStopped: идущий продолжается (RULE-76)
  pure def startIfStopped(t: Timer): Timer = if (t.mode == Running) t else startT(t)
  // resolution — pausable, startsOnce: пауза сохраняет остаток, а с ним и фазу;
  // продолжение с остатка, ещё не запускавшийся запускается с полного норматива.
  // Истёкший и сработавший остаётся сработавшим (RULE-50)
  pure def pauseT(t: Timer): Timer = if (t.mode == Running) { ...t, mode: Paused } else t
  pure def resumeT(t: Timer): Timer =
    if (t.mode == Paused) { ...t, mode: Running }
    else if (t.mode == Idle) { mode: Running, phase: Before }
    else t
  // restartTimer: заново, без остатка (RULE-11)
  pure def restartT(t: Timer): Timer = { mode: Running, phase: Before }
  pure def isDue(t: Timer): bool = t.mode == Running and t.phase == Due
  pure def markFired(t: Timer): Timer = { ...t, phase: Fired }

  /* ===== Люди, права, доступ (§2.4, §5, §8.1) ===== */

  pure def isGroup(id: str): bool = id == GROUP
  pure def addressee(x: Incident): str = if (x.owner != NOBODY) x.owner else x.group

  def can(a: str, p: str): bool = cfg.perms.get(a).contains(p)
  // «Я» как адресат: сам оператор и группа, в которую он входит
  def isSelf(a: str, id: str): bool = id != NOBODY and (id == a or (isGroup(id) and cfg.members.contains(a)))
  def isMine(a: str, x: Incident): bool = x.owner == a
  def isTarget(a: str, x: Incident): bool = isSelf(a, addressee(x))
  // Отношение смотрящего к инциденту: ожидающий моего принятия — «мне адресован», даже если
  // владельцем записан я сам (BUG-60)
  def ownership(a: str, x: Incident): str =
    if (x.state == Pending and isTarget(a, x)) "target"
    else if (isMine(a, x)) "owner"
    else if (isTarget(a, x)) "target"
    else "other"

  // Человеку — по своим группам доступа, группе — хотя бы одному участнику
  def hasAccess(who: str, i: str): bool =
    if (isGroup(who)) cfg.members.exists(m => cfg.access.get(m).contains(i))
    else OPERATORS.contains(who) and cfg.access.get(who).contains(i)
  // Принять может: право incident:accept и доступ; у группы — хотя бы один такой участник
  def canAcceptP(m: str, i: str): bool = can(m, "incident:accept") and cfg.access.get(m).contains(i)
  def canAccept(who: str, i: str): bool =
    if (isGroup(who)) cfg.members.exists(m => canAcceptP(m, i))
    else OPERATORS.contains(who) and canAcceptP(who, i)
  // То же, но участник except не в счёт: у него инцидент уже есть (RULE-93)
  def canAcceptExcept(who: str, i: str, except: str): bool =
    if (isGroup(who)) cfg.members.exists(m => m != except and canAcceptP(m, i))
    else canAccept(who, i)

  /* ===== Условия (registries.guards) ===== */

  // withinActiveLimit / withinHoldLimit: свои в этом состоянии, не считая самого инцидента
  def mineIn(a: str, s: State, i: str): int =
    INCIDENTS.filter(j => j != i and inc.get(j).state == s and isMine(a, inc.get(j))).size()
  def withinActiveLimit(a: str, i: str): bool = cfg.maxActive == 0 or mineIn(a, InProgress, i) < cfg.maxActive
  def withinHoldLimit(a: str, i: str): bool = cfg.maxOnHold == 0 or mineIn(a, OnHold, i) < cfg.maxOnHold

  // hasScopedPermission у «Передать»: own — новый, мой или мне адресован; иначе any
  def transferPermitted(a: str, x: Incident): bool = {
    val own = x.state == New or isMine(a, x) or isTarget(a, x)
    can(a, if (own) "incident:transfer:own" else "incident:transfer:any")
  }

  def closeResultAllowed(a: str, x: Incident, r: CloseResult, stepsFilled: bool): bool = all {
    can(a, r.perm),
    r.from.contains(x.state),
    not(r.ownerOnly.contains(x.state)) or isMine(a, x),
    not(r.steps) or stepsFilled,
  }

  // escalationTargetAvailable: ближайший уровень выше текущего, не выше потолка, адресат
  // которого может принять; остальные пропускаются. Пропускается и уровень, где принять может
  // только тот, у кого инцидент уже есть: его адресат или группа, где принять может только
  // владелец (RULE-93). LEVELS упорядочены по возрастанию
  def nextLevels(x: Incident, i: str): List[{ level: int, target: str }] =
    LEVELS.select(l => all {
      l.level > x.level,
      l.level <= MAX_LEVEL,
      l.target != addressee(x),
      canAcceptExcept(l.target, i, x.owner),
    })
  def escalationTargetAvailable(x: Incident, i: str): bool = nextLevels(x, i).length() > 0

  /* ===== Переходы по таймеру: условия ===== */

  def autoEscalateOk(i: str): bool = {
    val x = inc.get(i)
    x.state.in(Set(New, Pending)) and cfg.escalationEnabled and isDue(x.reaction) and escalationTargetAvailable(x, i)
  }
  def escalationCeilingOk(i: str): bool = {
    val x = inc.get(i)
    x.state.in(Set(New, Pending)) and cfg.escalationEnabled and isDue(x.reaction) and not(escalationTargetAvailable(x, i))
  }
  def reactionOverdueOk(i: str): bool = {
    val x = inc.get(i)
    x.state.in(Set(New, Pending)) and not(cfg.escalationEnabled) and isDue(x.reaction)
  }
  def resolutionOverdueOk(i: str): bool = {
    val x = inc.get(i)
    x.state == InProgress and isDue(x.resolution) and cfg.onResolutionOverdue == "alert"
  }
  def resolutionEscalateOk(i: str): bool = {
    val x = inc.get(i)
    x.state == InProgress and cfg.onResolutionOverdue == "escalate" and isDue(x.resolution) and escalationTargetAvailable(x, i)
  }
  def resolutionCeilingOk(i: str): bool = {
    val x = inc.get(i)
    x.state == InProgress and cfg.onResolutionOverdue == "escalate" and isDue(x.resolution) and not(escalationTargetAvailable(x, i))
  }
  def holdOverdueOk(i: str): bool = {
    val x = inc.get(i)
    x.state == OnHold and isDue(x.hold)
  }

  // Готовые переходы по таймеру — пока они есть, ручные действия над инцидентом ждут
  def timerTransitionsReady(i: str): Set[str] = Set(
    if (autoEscalateOk(i)) Set("auto_escalate") else Set(),
    if (escalationCeilingOk(i)) Set("escalation_ceiling") else Set(),
    if (reactionOverdueOk(i)) Set("reaction_overdue") else Set(),
    if (resolutionOverdueOk(i)) Set("resolution_overdue") else Set(),
    if (resolutionEscalateOk(i)) Set("resolution_escalate") else Set(),
    if (resolutionCeilingOk(i)) Set("resolution_ceiling") else Set(),
    if (holdOverdueOk(i)) Set("hold_overdue") else Set(),
  ).flatten()
  def manualAllowed(i: str): bool = timerTransitionsReady(i) == Set()

  /* ===== Применение перехода ===== */

  // Права, доступ и настройки не меняются — каждое действие сохраняет cfg, поэтому его можно
  // выполнить и само по себе (сценарии im_test.qnt)
  action apply(name: str, actor: str, i: str, x: Incident): bool = all {
    cfg' = cfg,
    inc' = inc.set(i, x),
    lastAction' = { name: name, actor: actor, incident: i },
  }

  /* ===== Событие: появление инцидента (create) ===== */

  action create(i: str): bool = all {
    inc.get(i).state == Absent,
    apply("create", DISPATCHER, i, { ...ABSENT,
      state: New,
      owner: NOBODY,
      group: NOBODY,
      level: 0,
      reaction: startT(IDLE),
    }),
  }

  /* ===== Ручные переходы (§6.1) =====
     У каждого — условие <id>Ok (from + guards машины) и действие с эффектами. Условие
     отдельно — так сценарии проверяют и запреты: not(claimOk("a", "i1")) */

  def claimOk(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      x.state == New,
      manualAllowed(i),
      can(a, "incident:claim"),
      withinActiveLimit(a, i),
    }
  }
  action claim(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      claimOk(a, i),
      apply("claim", a, i, { ...x,
        state: InProgress,
        owner: a,
        reaction: stopT(x.reaction),
        resolution: resumeT(x.resolution),
      }),
    }
  }

  def acceptOk(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      x.state == Pending,
      manualAllowed(i),
      can(a, "incident:accept"),
      isTarget(a, x),
      withinActiveLimit(a, i),
    }
  }
  action accept(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      acceptOk(a, i),
      apply("accept", a, i, { ...x,
        state: InProgress,
        owner: a,
        group: NOBODY,
        reaction: stopT(x.reaction),
        resolution: resumeT(x.resolution),
      }),
    }
  }

  def rejectOk(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      x.state == Pending,
      manualAllowed(i),
      can(a, "incident:release"),
      isTarget(a, x),
    }
  }
  // Реакция продолжается (continuesOn, RULE-82)
  action reject(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      rejectOk(a, i),
      apply("reject", a, i, { ...x, state: New, owner: NOBODY, group: NOBODY }),
    }
  }

  def holdOk(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      x.state == InProgress,
      manualAllowed(i),
      can(a, "incident:hold"),
      isMine(a, x),
      withinHoldLimit(a, i),
    }
  }
  action hold(a: str, i: str, reason: str): bool = {
    val x = inc.get(i)
    all {
      holdOk(a, i),
      apply("hold", a, i, { ...x,
        state: OnHold,
        holdReason: reason,
        resolution: pauseT(x.resolution),
        hold: startT(x.hold),
      }),
    }
  }

  def resumeOk(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      x.state == OnHold,
      manualAllowed(i),
      can(a, "incident:claim"),
      isMine(a, x),
      withinActiveLimit(a, i),
    }
  }
  action resume(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      resumeOk(a, i),
      apply("resume", a, i, { ...x,
        state: InProgress,
        holdReason: NOBODY,
        hold: stopT(x.hold),
        resolution: resumeT(x.resolution),
      }),
    }
  }

  def releaseOk(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      x.state.in(Set(InProgress, OnHold)),
      manualAllowed(i),
      can(a, "incident:release"),
      isMine(a, x),
    }
  }
  action release(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      releaseOk(a, i),
      apply("release", a, i, { ...x,
        state: New,
        owner: NOBODY,
        holdReason: NOBODY,
        resolution: pauseT(x.resolution),
        hold: stopT(x.hold),
        reaction: startT(x.reaction),
      }),
    }
  }

  def transferOk(a: str, i: str, t: str): bool = {
    val x = inc.get(i)
    all {
      x.state.in(Set(New, Pending, InProgress, OnHold)),
      manualAllowed(i),
      transferPermitted(a, x),
      not(isSelf(a, t)),   // targetIsNotSelf
      hasAccess(t, i),     // targetHasAccess; targetHasAccessToLinked — привязанных в ядре нет
      canAccept(t, i),     // targetCanAccept
    }
  }
  action transfer(a: str, i: str, t: str): bool = {
    val x = inc.get(i)
    all {
      transferOk(a, i, t),
      apply("transfer", a, i, { ...x,
        state: Pending,
        owner: if (isGroup(t)) NOBODY else t,
        group: if (isGroup(t)) t else NOBODY,
        transfers: x.transfers + 1,
        holdReason: NOBODY,
        resolution: pauseT(x.resolution),
        hold: stopT(x.hold),
        reaction: startIfStopped(x.reaction),
      }),
    }
  }

  def takeoverOk(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      x.state.in(Set(Pending, InProgress, OnHold)),
      manualAllowed(i),
      can(a, "incident:reassign"),
      can(a, "incident:claim"),
      ownership(a, x) != "owner",   // isNotOwner
      ownership(a, x) != "target",  // isNotTarget
      withinActiveLimit(a, i),
    }
  }
  action takeover(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      takeoverOk(a, i),
      apply("takeover", a, i, { ...x,
        state: InProgress,
        owner: a,
        group: NOBODY,
        holdReason: NOBODY,
        reaction: stopT(x.reaction),
        hold: stopT(x.hold),
        resolution: resumeT(x.resolution),
      }),
    }
  }

  // stepsFilled — заполнены ли шаги набора closing (машина сценариев, §14.5)
  def closeOk(a: str, i: str, r: CloseResult, stepsFilled: bool): bool = {
    val x = inc.get(i)
    all {
      x.state.in(Set(New, Pending, InProgress, OnHold)),
      manualAllowed(i),
      closeResultAllowed(a, x, r, stepsFilled),
    }
  }
  action close(a: str, i: str, r: CloseResult, stepsFilled: bool): bool = {
    val x = inc.get(i)
    all {
      closeOk(a, i, r, stepsFilled),
      apply("close", a, i, { ...x,
        state: Closed,
        owner: a,
        group: NOBODY,
        closedBy: a,
        closeResult: r.id,
        holdReason: NOBODY,
        reaction: stopT(x.reaction),
        resolution: pauseT(x.resolution),
        hold: stopT(x.hold),
        reopenOpen: true,
      }),
    }
  }

  def reopenOk(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      x.state == Closed,
      can(a, "incident:reopen"),
      can(a, "incident:claim"),
      x.reopenOpen,
      withinActiveLimit(a, i),
    }
  }
  // restartTimer resolution, limits.reopenResolutionSec или обычный норматив
  action reopen(a: str, i: str): bool = {
    val x = inc.get(i)
    all {
      reopenOk(a, i),
      apply("reopen", a, i, { ...x,
        state: InProgress,
        owner: a,
        closeResult: NOBODY,
        resolution: restartT(x.resolution),
      }),
    }
  }

  /* ===== Переходы по таймеру (§4, §9) ===== */

  // Сработавший дедлайн отмечается до эффектов (markFired в tick прототипа)
  def breach(x: Incident, kind: str): List[Breach] = x.breaches.append({ kind: kind, who: addressee(x) })

  action autoEscalate(i: str): bool = {
    val x = inc.get(i)
    val l = nextLevels(x, i)[0]
    all {
      autoEscalateOk(i),
      apply("auto_escalate", DISPATCHER, i, { ...x,
        state: Pending,
        owner: if (isGroup(l.target)) NOBODY else l.target,
        group: if (isGroup(l.target)) l.target else NOBODY,
        level: l.level,
        holdReason: NOBODY,
        resolution: pauseT(x.resolution),
        reaction: startT(markFired(x.reaction)),
      }),
    }
  }

  action escalationCeiling(i: str): bool = {
    val x = inc.get(i)
    all {
      escalationCeilingOk(i),
      apply("escalation_ceiling", DISPATCHER, i, { ...x,
        breaches: breach(x, "reaction"),
        reaction: stopT(markFired(x.reaction)),
      }),
    }
  }

  action reactionOverdue(i: str): bool = {
    val x = inc.get(i)
    all {
      reactionOverdueOk(i),
      apply("reaction_overdue", DISPATCHER, i, { ...x,
        breaches: breach(x, "reaction"),
        reaction: stopT(markFired(x.reaction)),
      }),
    }
  }

  action resolutionOverdue(i: str): bool = {
    val x = inc.get(i)
    all {
      resolutionOverdueOk(i),
      apply("resolution_overdue", DISPATCHER, i, { ...x,
        breaches: breach(x, "resolution"),
        resolution: markFired(x.resolution),
      }),
    }
  }

  action resolutionEscalate(i: str): bool = {
    val x = inc.get(i)
    val l = nextLevels(x, i)[0]
    all {
      resolutionEscalateOk(i),
      apply("resolution_escalate", DISPATCHER, i, { ...x,
        state: Pending,
        breaches: breach(x, "resolution"),
        owner: if (isGroup(l.target)) NOBODY else l.target,
        group: if (isGroup(l.target)) l.target else NOBODY,
        level: l.level,
        resolution: pauseT(markFired(x.resolution)),
        reaction: startT(x.reaction),
      }),
    }
  }

  action resolutionCeiling(i: str): bool = {
    val x = inc.get(i)
    all {
      resolutionCeilingOk(i),
      apply("resolution_ceiling", DISPATCHER, i, { ...x,
        breaches: breach(x, "resolution"),
        resolution: markFired(x.resolution),
      }),
    }
  }

  action holdOverdue(i: str): bool = {
    val x = inc.get(i)
    all {
      holdOverdueOk(i),
      apply("hold_overdue", DISPATCHER, i, { ...x,
        breaches: breach(x, "hold"),
        hold: markFired(x.hold),
      }),
    }
  }

  /* ===== Окружение: время ===== */

  def expireReactionOk(i: str): bool = inc.get(i).reaction.mode == Running and inc.get(i).reaction.phase == Before
  action expireReaction(i: str): bool = {
    val x = inc.get(i)
    all {
      expireReactionOk(i),
      apply("expire_reaction", NOBODY, i, { ...x, reaction: { ...x.reaction, phase: Due } }),
    }
  }

  def expireResolutionOk(i: str): bool = inc.get(i).resolution.mode == Running and inc.get(i).resolution.phase == Before
  action expireResolution(i: str): bool = {
    val x = inc.get(i)
    all {
      expireResolutionOk(i),
      apply("expire_resolution", NOBODY, i, { ...x, resolution: { ...x.resolution, phase: Due } }),
    }
  }

  def expireHoldOk(i: str): bool = inc.get(i).hold.mode == Running and inc.get(i).hold.phase == Before
  action expireHold(i: str): bool = {
    val x = inc.get(i)
    all {
      expireHoldOk(i),
      apply("expire_hold", NOBODY, i, { ...x, hold: { ...x.hold, phase: Due } }),
    }
  }

  action expireReopenWindow(i: str): bool = {
    val x = inc.get(i)
    all {
      x.state == Closed and x.reopenOpen,
      apply("expire_reopen_window", NOBODY, i, { ...x, reopenOpen: false }),
    }
  }

  /* ===== Начало и шаг ===== */

  action init = {
    nondet perms = OPERATORS.setOfMaps(PERMS.powerset()).oneOf()
    nondet access = OPERATORS.setOfMaps(INCIDENTS.powerset()).oneOf()
    nondet members = OPERATORS.powerset().oneOf()
    nondet escalationEnabled = Set(true, false).oneOf()
    nondet onResolutionOverdue = Set("alert", "escalate").oneOf()
    nondet maxActive = Set(0, 1).oneOf()
    nondet maxOnHold = Set(0, 1).oneOf()
    all {
      cfg' = {
        perms: perms, access: access, members: members,
        escalationEnabled: escalationEnabled, onResolutionOverdue: onResolutionOverdue,
        maxActive: maxActive, maxOnHold: maxOnHold,
      },
      inc' = INCIDENTS.mapBy(i => ABSENT),
      lastAction' = { name: "init", actor: NOBODY, incident: NOBODY },
    }
  }

  action step = {
    nondet i = INCIDENTS.oneOf()
    nondet a = OPERATORS.oneOf()
    nondet t = TARGETS.oneOf()
    nondet reason = HOLD_REASONS.oneOf()
    nondet r = CLOSE_RESULTS.oneOf()
    nondet stepsFilled = Set(true, false).oneOf()
    any {
      create(i),
      claim(a, i),
      accept(a, i),
      reject(a, i),
      hold(a, i, reason),
      resume(a, i),
      release(a, i),
      transfer(a, i, t),
      takeover(a, i),
      close(a, i, r, stepsFilled),
      reopen(a, i),
      autoEscalate(i),
      escalationCeiling(i),
      reactionOverdue(i),
      resolutionOverdue(i),
      resolutionEscalate(i),
      resolutionCeiling(i),
      holdOverdue(i),
      expireReaction(i),
      expireResolution(i),
      expireHold(i),
      expireReopenWindow(i),
    }
  }

  /* ===== Инварианты =====
     quint run im.qnt --invariants inv
     Каждый можно проверить отдельно — имена ниже. */

  pure def hasBreach(x: Incident, kind: str): bool = x.breaches.select(b => b.kind == kind).length() > 0

  // 1. Владелец по состоянию (§2.1)
  val ownerByState = INCIDENTS.forall(i => {
    val x = inc.get(i)
    match x.state {
      | Absent => true
      | New => x.owner == NOBODY and x.group == NOBODY
      | Pending =>
          (OPERATORS.contains(x.owner) and x.group == NOBODY)
          or (x.owner == NOBODY and x.group == GROUP)
      | InProgress => OPERATORS.contains(x.owner) and x.group == NOBODY
      | OnHold => OPERATORS.contains(x.owner) and x.group == NOBODY
      | Closed => OPERATORS.contains(x.owner) and x.owner == x.closedBy and x.group == NOBODY
    }
  })

  // 2. Причина удержания задана ⇔ on_hold
  val holdReasonIffOnHold = INCIDENTS.forall(i => {
    val x = inc.get(i)
    (x.holdReason != NOBODY) iff (x.state == OnHold)
  })

  // 3. Таймеры по состоянию (timers: startsOnEnter, stopsOnEnter, pausedInStates).
  //    Реакция в new / pending остановлена только потолком или нарушением — тогда
  //    нарушение реакции записано (RULE-84). Сработавшая реакция не идёт дальше: её переходы
  //    либо запускают новый дедлайн, либо останавливают — иначе «Передать» (ifStopped) её не
  //    перезапустит и инцидент останется без норматива
  val timersByState = INCIDENTS.forall(i => {
    val x = inc.get(i)
    not(x.reaction.mode == Running and x.reaction.phase == Fired) and match x.state {
      | Absent => true
      | New =>
          x.hold.mode == Idle and x.resolution.mode != Running
          and (x.reaction.mode == Running or (x.reaction.mode == Idle and hasBreach(x, "reaction")))
      | Pending =>
          x.hold.mode == Idle and x.resolution.mode != Running
          and (x.reaction.mode == Running or (x.reaction.mode == Idle and hasBreach(x, "reaction")))
      | InProgress => x.resolution.mode == Running and x.reaction.mode == Idle and x.hold.mode == Idle
      | OnHold => x.hold.mode == Running and x.resolution.mode == Paused and x.reaction.mode == Idle
      | Closed => x.reaction.mode != Running and x.resolution.mode != Running and x.hold.mode != Running
    }
  })

  // 4. Уровень эскалации в пределах (§8.3)
  val levelBounded = INCIDENTS.forall(i => inc.get(i).level >= 0 and inc.get(i).level <= MAX_LEVEL)

  // 5. Результат закрытия задан ⇔ closed (§2.2)
  val closeResultIffClosed = INCIDENTS.forall(i => {
    val x = inc.get(i)
    (x.closeResult != NOBODY) iff (x.state == Closed)
  })

  // 6. Взаимоисключение: по инциденту готово не больше одного перехода по таймеру (§14.3)
  val timerTransitionsExclusive = INCIDENTS.forall(i => timerTransitionsReady(i).size() <= 1)

  // 7. Полнота: наступивший дедлайн идущего таймера кто-то обрабатывает — не теряется молча (§4, §9)
  val dueDeadlineHandled = INCIDENTS.forall(i => {
    val x = inc.get(i)
    (isDue(x.reaction) or isDue(x.resolution) or isDue(x.hold)) implies timerTransitionsReady(i) != Set()
  })

  // 8. Лимиты (§10.2); в ядре все удержания ручные, поэтому maxOnHold — для всех отложенных
  def countMine(a: str, s: State): int = INCIDENTS.filter(j => inc.get(j).state == s and isMine(a, inc.get(j))).size()
  val limitsRespected = OPERATORS.forall(a => all {
    cfg.maxActive == 0 or countMine(a, InProgress) <= cfg.maxActive,
    cfg.maxOnHold == 0 or countMine(a, OnHold) <= cfg.maxOnHold,
  })

  // 9. У ожидающего принятия адресат может принять (§8.1); в ядре права и доступ не меняются
  val pendingAddresseeCanAccept = INCIDENTS.forall(i => {
    val x = inc.get(i)
    x.state == Pending implies canAccept(addressee(x), i)
  })

  // 10. Эскалация не адресует инцидент тому, у кого он уже есть: тому же человеку, той же группе
  //     или группе, где принять может только его владелец — как «Исключение владельца» ручной
  //     передачи (§8.1, §8.3, RULE-93). Иначе просрочка закрытия не дошла бы до старшего, а не
  //     принявший вовремя получил бы новый срок реакции без нарушения
  def escalatesToCurrentAddressee(i: str): bool = {
    val x = inc.get(i)
    val t = nextLevels(x, i)[0].target
    escalationTargetAvailable(x, i) and (
      t == addressee(x)
      or (isGroup(t) and not(cfg.members.exists(m => m != x.owner and canAcceptP(m, i))))
    )
  }
  val autoEscalateNotToCurrentAddressee = INCIDENTS.forall(i => autoEscalateOk(i) implies not(escalatesToCurrentAddressee(i)))
  val resolutionEscalateNotToCurrentAddressee = INCIDENTS.forall(i => resolutionEscalateOk(i) implies not(escalatesToCurrentAddressee(i)))

  val inv = all {
    ownerByState,
    holdReasonIffOnHold,
    timersByState,
    levelBounded,
    closeResultIffClosed,
    timerTransitionsExclusive,
    dueDeadlineHandled,
    limitsRespected,
    pendingAddresseeCanAccept,
    autoEscalateNotToCurrentAddressee,
    resolutionEscalateNotToCurrentAddressee,
  }
}
