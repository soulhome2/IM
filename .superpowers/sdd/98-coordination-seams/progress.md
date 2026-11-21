# SDD ledger — plan: research/integration/98-coordination-seams.md

Сервер: ~/Work/incident-manager-server, ветка feature/im_operator, старт с 6f62266. Спек отдельного нет — план и его решения 1–7 (приняты 2026-11-21) и есть авторитет.

## Pre-flight
| Задачи | Общее | Находка |
|---|---|---|
| 1→2,3,5 | coord.Key/Class/Locker | 2,3,5 потребляют интерфейсы задачи 1; согласовано |
| 3→5 | замок сессии pgcoord | Leader — try-без-ожидания поверх той же механики соединения; Holder.Hold ждёт. Не конфликт |
| 4→6 | hub.go | страж 6 должен пропустить pgcoord; hub после 4 без LISTEN — ок |
| 2→6 | storing/stream_queries.go | З1 остаётся SQL, страж его исключает явно — согласовано |
| 1 | сама с собой | ок |
| 2 | «ключи те же» (шаг 1) vs решение 3 меняет ключи З7/З8 | ок: шаг 1 о З2–З6 |
| 3 | ок | |
| 4 | fakeConn → memcoord (решение 6) | ок |
| 5 | тест «NewLeader не берёт соединение» | ок |
| 6 | страж «строки pg_advisory/LISTEN » vs комментарии в transition/pgrepo.go:154, stream/hub.go:65 | см. Ruling |

Ruling: страж задачи 6 смотрит строковые литералы Go (go/parser), не комментарии — комментарии ничего не координируют, а слово LISTEN в прозе ложно сработало бы — если неверно: пара строк в стражe, переписать на построчный поиск.
Ruling: ADR-008 ссылаются и ADR-005, и ADR-006 (просьба пользователя шире шага 6.2) — без цены.

## Задачи
Task 1: dispatched (BASE 6f62266, implementer ab1c17fadf0d94a24)
Task 1: implementer DONE_WITH_CONCERNS 6a62509 (minor concerns: New() name, lock_timeout in tests); review dispatched abbb1ed0d1e9026ef
Task 1: complete (commits 6f62266..6a62509, review clean; 4 Minor parked: weak 2nd requireWaits in TestLockSharedTogether, parser sees only `X Class = N`, failure path up to 10s, typed-nil only for Lock)
Ruling: pgcoord.New переименовать в NewLocker в задаче 2 (она подключает Locker в appservice.go) — имена Holder/Leader без путаницы — цена: одна правка имени.
Task 2: dispatched (BASE 6a62509)
Task 2: implementer DONE_WITH_CONCERNS 6f30b06 (InsertEventIfNew in DoInTx; Locker via Store.Locker(); 3 stand tests 428 also on BASE)
Task 2: complete (commits 6a62509..6f30b06, review clean; per-lock table all ✅, 36/36 mutations killed; Minor parked: nil Locker in reset/backup panics, coord_locks_test intake case needs migrated DB, Store.Locker() as hand-out point → plan 99 may move to Infrastructure)
Note: 3 stand tests in handler/test 428 (TestStandJournalLinesOfSetFirst, TestStandResetForgetsScripts, TestStandNoOldEventTypes) — implementer says fail on BASE too; recheck in full run on a fresh test DB.
Task 3: dispatched (BASE 6f30b06)
Task 3: implementer DONE_WITH_CONCERNS ef63f6f — build runs on 2nd connection, not the lock's (behaviour change) → asking user
Decision (user 2026-11-21): Hold returns (lockCtx, release, err); pgcoord checks lock conn every poll (SELECT 1), cancels lockCtx on loss; build runs on lockCtx; memcoord cancels on Drop.
Task 3 review: Needs fixes (Important 1 = lock-loss; Minor 3 rewrap). Fix round 1 sent to implementer.
Task 3: complete (commits 6f30b06..80d4c4b, review clean after round 1; Minor parked: TestSearchIndexesLockLost cancels held before Conn — later statements on ctx would survive; Store.Pool() exposes *sql.DB)
Task 4: dispatched (BASE 80d4c4b)
Task 4: implementer DONE 10d3729; review dispatched
Task 4: complete (commits 80d4c4b..10d3729, review clean; Minor parked: TestHubReconnectWakesAll doesn't check sub.Close on break branch; memcoord Close doesn't end waiting Next (contract weaker); memcoord Listen ignores ctx; const channel duplicate w/o comment)
Task 5: dispatched (BASE 10d3729)
Task 5: implementer DONE aea6731 (Holder.release → shared unhold; Resign 5s timeout); review dispatched
Task 5 review: Approved with ⚠️ (decision 6: LeadEndsWithContext not shared) + Minor 1 (pg drops role on ended ctx). Fix round 1 sent. Minor parked for ADR: resignTimeout 5s.
Task 5: complete (commits 10d3729..efaac98, review clean after round 1)
Ruling: задача 6 — страж и ADR без коммита; потом полный прогон -race, стенд, затем один коммит (шаг 4: «только потом коммит»).
Task 6: dispatched (BASE efaac98) — steps 1–2
Task 6 steps 1-2: implementer DONE (uncommitted: guard_test.go, ADR-008, ADR-005/006). Full -race run started (bqywvtv2m) on fresh test DB.
Task 6 review: Needs fixes (ADR-006 access-cache wording invented; ADR-008 minor 1,2). Fix round 1 sent (md only). Minor parked: guard root hard-coded ../../../.., split literals / LISTEN<tab> pass guard.
Task 6 steps 1-2: review clean after round 1 (wording of З8 line fixed by controller)
Стенд: копия imdb → backup/imdb-before-p98-2026-11-21.dump
Стенд: копия imdb → ~/Work/stand/backup/imdb-before-p98-2026-11-21.dump (docker exec ac_db pg_dump -Fc)
Task 6 step 3: full go test -race -p 1 ./... on fresh test DB — exit 0, 32 ok, 0 FAIL (HEAD efaac98 + uncommitted guard/docs); 3 stand 428 tests green on fresh DB
Final review: Ready with 3 text fixes (comment LockIntakeSQL in session_lock_order_test.go, ADR-006:49 stale leader line, ADR-008 "two rules"→three) + list of small behaviour changes in ADR-008. Fix wave dispatched to task-6 implementer.
To plan 99 (from final triage): Store.Locker()/Pool() hand-out + build coord in one place (Infrastructure; Listener now in appservice.go); memcoord Close doesn't end waiting Next; memcoord Listen ignores ctx.
Final review fix wave: approved (ADR-008:6 nit fixed by controller)
Стенд: все проверки ✅ (stand-report.md). Сброс удалил инциденты (копия МИ — только настройки) → imdb возвращена из imdb-before-p98-2026-11-21.dump (pg_restore без EXTENSION/SCHEMA public, 174 155 инцидентов); сервер im-p98-efaac98, индексы ready.
Task 6: complete (server 01252a3: guard + ADR-008 + ADR-005/006 + comment).
Plan 98: CLOSED. Итог — в плане.
