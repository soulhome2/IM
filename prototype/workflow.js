// Собрано из Specification/State_machine/workflow.v4.json скриптом tools/build_workflow.py.
// Руками не править: правится исходник, затем сборка.
window.IM_WORKFLOW = {
  "$comment": "Единая JSON-модель workflow операторской части МИ. Соответствует действующим правилам Specification/State_rules/States rules IM.md, версия v8, и изменениям после неё по журналу State_rules/CHANGELOG.md (§16). Формат записи перехода — §14.8. Это конфигурация: бэкенд её хранит, валидирует и исполняет; фронтенд по ней рисует кнопки, формы и бейджи и ничего не зашивает в код. Автоматические переходы, готовые одновременно, выполняются по времени наступления условия (таймер — дедлайн, потеря связи — порог), при равенстве — по порядку в transitions (§14.3).",
  "schema": {
    "id": "im.operator.incident",
    "version": 4,
    "status": "published",
    "name": "Обработка инцидента оператором",
    "publishedAt": "2026-09-28T07:00:00Z",
    "publishedBy": null,
    "appliesTo": {
      "$comment": "§14.4. Схема привязывается к типу события, группе устройств и приоритету. Конфликты разрешаются по специфичности условия; при равной специфичности выигрывает схема с большим weight.",
      "default": true,
      "weight": 0,
      "eventTypeGuids": null,
      "sourceGroupGuids": null,
      "priorities": null
    },
    "stateMapping": {
      "$comment": "§14.6. Сопоставление состояний предыдущей версии при публикации. Пусто — состояния не переименовывались."
    }
  },
  "stateCategories": [
    {
      "id": "pending",
      "label": "Ожидают",
      "countsAsOpen": true
    },
    {
      "id": "active",
      "label": "В работе",
      "countsAsOpen": true
    },
    {
      "id": "done",
      "label": "Завершены",
      "countsAsOpen": false
    }
  ],
  "states": [
    {
      "id": "new",
      "$comment": "§2.1, §3 (RULE-46). Начальное: инцидент появляется в этом состоянии — событие от основной системы.",
      "label": "Новое",
      "labelKey": "workflow.state.new",
      "category": "pending",
      "initial": true,
      "terminal": false,
      "owner": "none",
      "activeTimer": "reaction"
    },
    {
      "id": "pending_acceptance",
      "label": "Ожидает принятия",
      "labelKey": "workflow.state.pending_acceptance",
      "category": "pending",
      "terminal": false,
      "owner": "transfer_target",
      "activeTimer": "reaction"
    },
    {
      "id": "in_progress",
      "label": "В работе",
      "labelKey": "workflow.state.in_progress",
      "category": "active",
      "terminal": false,
      "owner": "operator",
      "activeTimer": "resolution"
    },
    {
      "id": "on_hold",
      "label": "Отложен",
      "labelKey": "workflow.state.on_hold",
      "category": "active",
      "terminal": false,
      "owner": "operator",
      "activeTimer": "resolution_paused"
    },
    {
      "id": "closed",
      "label": "Закрыто",
      "labelKey": "workflow.state.closed",
      "category": "done",
      "terminal": true,
      "owner": "closed_by",
      "activeTimer": null
    }
  ],
  "badges": {
    "$comment": "§2.4. Бейдж не хранится — вычисляется сервером под смотрящего оператора и отдаётся в поле badge каждой записи очереди.",
    "rules": [
      {
        "state": "new",
        "viewerRole": "any",
        "label": "Новое",
        "style": "new"
      },
      {
        "state": "pending_acceptance",
        "viewerRole": "target",
        "when": {
          "addressee": "group"
        },
        "label": "Вашей группе · {ownerName}",
        "style": "inbox"
      },
      {
        "state": "pending_acceptance",
        "viewerRole": "target",
        "label": "Вам на принятие",
        "style": "inbox"
      },
      {
        "state": "pending_acceptance",
        "viewerRole": "other",
        "label": "Ожидает принятия · {ownerName}",
        "style": "escalated"
      },
      {
        "state": "in_progress",
        "viewerRole": "owner",
        "label": "В работе",
        "style": "mine"
      },
      {
        "state": "in_progress",
        "viewerRole": "other",
        "label": "{ownerName}",
        "style": "foreign"
      },
      {
        "state": "on_hold",
        "viewerRole": "owner",
        "label": "Отложен · {holdReasonLabel}",
        "style": "paused"
      },
      {
        "state": "on_hold",
        "viewerRole": "other",
        "label": "Отложен · {ownerName}",
        "style": "paused"
      },
      {
        "state": "closed",
        "viewerRole": "any",
        "when": {
          "closeResult": "processed"
        },
        "label": "Закрыто",
        "style": "done"
      },
      {
        "state": "closed",
        "viewerRole": "any",
        "label": "Закрыто · {closeResultLabel}",
        "style": "done_unprocessed"
      }
    ]
  },
  "permissions": [
    {
      "key": "incident:claim",
      "label": "Взять новое, возобновить свой отложенный; перехватить и переоткрыть — вместе с их правами. Без него инцидент в работу не попадает"
    },
    {
      "key": "incident:accept",
      "label": "Принять переданное мне или моей дежурной группе"
    },
    {
      "key": "incident:hold",
      "label": "Отложить свой инцидент с указанием причины"
    },
    {
      "key": "incident:release",
      "label": "Вернуть свой инцидент в очередь; отклонить адресованную передачу"
    },
    {
      "key": "incident:close",
      "label": "Закрыть свой инцидент с результатом: «Обработан» — после обязательных шагов; «Ложная тревога», «Дубликат», «Плановая проверка», «Прервано» — без сценария"
    },
    {
      "key": "incident:close:unprocessed",
      "label": "Закрыть с результатом «Массовый сбой» без сценария, в том числе не беря в работу"
    },
    {
      "key": "incident:reopen",
      "label": "Вернуть в работу закрытый инцидент"
    },
    {
      "key": "incident:transfer:own",
      "label": "Передать своё, ничьё или адресованное мне"
    },
    {
      "key": "incident:transfer:any",
      "label": "Передать инцидент, занятый другим оператором"
    },
    {
      "key": "incident:reassign",
      "label": "Перехватить инцидент у работающего оператора"
    },
    {
      "key": "incident:read:any",
      "label": "Открыть карточку чужого инцидента только для чтения"
    },
    {
      "key": "incident:bulk",
      "label": "Обработать несколько инцидентов как один"
    },
    {
      "key": "incident:run_action",
      "label": "Запускать макросы и команды из карточки"
    },
    {
      "key": "incident:schema:admin",
      "label": "Менять схему, нормативы и настройки автоэскалации"
    },
    {
      "key": "agent:set_not_ready",
      "label": "Переводить себя в перерыв"
    }
  ],
  "timers": [
    {
      "id": "reaction",
      "label": "Реакция",
      "$comment": "§4, правило 2. Нормативы задаются на тип события, приоритет и группу устройств; в данных события норматива нет. Значение: самая специфичная строка overrides (больше совпавших условий), иначе byPriority, иначе defaultSec. Строка overrides: { eventType?, priority?, sourceGroup?, sec }. У реакции дополнительно escalationLevel — норматив уровня автоэскалации (§8.3).",
      "deadlineField": "reaction_due_at",
      "meaning": "Время от появления инцидента до взятия в работу",
      "startsOnEnter": [
        "new",
        "pending_acceptance"
      ],
      "continuesOn": [
        "addressee_signed_out_to_group",
        "addressee_signed_out_to_queue"
      ],
      "stopsOnEnter": [
        "in_progress",
        "closed"
      ],
      "pausable": false,
      "defaultSec": 300,
      "overridesBy": [
        "eventType",
        "priority",
        "sourceGroup",
        "escalationLevel"
      ],
      "overrides": [
        {
          "priority": "critical",
          "sec": 240
        },
        {
          "priority": "high",
          "sec": 420
        },
        {
          "priority": "medium",
          "sec": 900
        },
        {
          "priority": "low",
          "sec": 1800
        }
      ],
      "onExpire": "auto_escalate"
    },
    {
      "id": "resolution",
      "label": "Закрытие",
      "deadlineField": "resolution_due_at",
      "meaning": "Время от взятия в работу до закрытия",
      "$comment": "§4, правило 6 (RULE-07, RULE-11). Запускается при первом входе в in_progress. Передача, возврат в очередь, удержание и закрытие его только приостанавливают, взятие и принятие продолжают с остатка — так просрочку не скрыть. Переоткрытие запускает его заново (restartTimer, норматив limits.reopenResolutionSec или обычный): нарушения, записанные до закрытия, остаются в breaches.",
      "startsOnEnter": [
        "in_progress"
      ],
      "startsOnce": true,
      "stopsOnEnter": [],
      "pausable": true,
      "pausedInStates": [
        "new",
        "pending_acceptance",
        "on_hold",
        "closed"
      ],
      "defaultSec": 900,
      "byPriority": {
        "critical": 600,
        "high": 900,
        "medium": 1500,
        "low": 1800
      },
      "overridesBy": [
        "eventType",
        "priority",
        "sourceGroup"
      ],
      "overrides": [],
      "onExpire": "resolution_overdue"
    },
    {
      "id": "hold",
      "label": "Предельный срок удержания",
      "deadlineField": "hold_due_at",
      "meaning": "Сколько инцидент можно держать в on_hold по выбранной причине",
      "startsOnEnter": [
        "on_hold"
      ],
      "stopsOnEnter": [
        "in_progress",
        "new",
        "closed"
      ],
      "pausable": false,
      "secFrom": "reasonCatalogs.hold[].maxMinutes",
      "onExpire": "hold_overdue"
    }
  ],
  "reasonCatalogs": {
    "hold": {
      "field": "hold_reason",
      "requiredOnTransition": [
        "hold"
      ],
      "items": [
        {
          "id": "third_party",
          "label": "Ожидание третьей стороны",
          "maxMinutes": 30,
          "setBy": "operator"
        },
        {
          "id": "patrol",
          "label": "Выезд наряда",
          "maxMinutes": 45,
          "setBy": "operator"
        },
        {
          "id": "no_data",
          "label": "Нет данных, вернуться позже",
          "maxMinutes": 60,
          "setBy": "operator"
        },
        {
          "id": "break",
          "label": "Перерыв оператора",
          "maxMinutes": 30,
          "setBy": "system"
        },
        {
          "id": "no_link",
          "label": "Нет связи с оператором",
          "maxMinutes": 20,
          "setBy": "system"
        }
      ]
    },
    "close_result": {
      "$comment": "§2.2. Результат закрытия. Конечное состояние одно — closed, итог инцидента — только результат (RULE-02). Право, исходные состояния, владение, обязательные шаги и комментарий зависят от результата; проверяет их guard closeResultAllowed. Значения permission и fromStates решены (§2.2, §15). surfaces — где результат предлагается: из очереди только «Массовый сбой», остальные — из карточки (§7).",
      "field": "close_result",
      "requiredOnTransition": [
        "close"
      ],
      "items": [
        {
          "id": "processed",
          "label": "Обработан",
          "permission": "incident:close",
          "fromStates": [
            "in_progress"
          ],
          "ownerOnlyInStates": [
            "in_progress"
          ],
          "requiredStepSet": "closing",
          "commentRequired": false,
          "surfaces": [
            "card"
          ]
        },
        {
          "id": "false_alarm",
          "label": "Ложная тревога",
          "permission": "incident:close",
          "fromStates": [
            "in_progress"
          ],
          "ownerOnlyInStates": [
            "in_progress"
          ],
          "requiredStepSet": "none",
          "commentRequired": true,
          "surfaces": [
            "card"
          ]
        },
        {
          "id": "duplicate",
          "label": "Дубликат",
          "permission": "incident:close",
          "fromStates": [
            "in_progress"
          ],
          "ownerOnlyInStates": [
            "in_progress"
          ],
          "requiredStepSet": "none",
          "commentRequired": true,
          "surfaces": [
            "card"
          ]
        },
        {
          "id": "drill",
          "label": "Плановая проверка",
          "permission": "incident:close",
          "fromStates": [
            "in_progress"
          ],
          "ownerOnlyInStates": [
            "in_progress"
          ],
          "requiredStepSet": "none",
          "commentRequired": true,
          "surfaces": [
            "card"
          ]
        },
        {
          "id": "impossible",
          "label": "Прервано: обработка невозможна",
          "permission": "incident:close",
          "fromStates": [
            "in_progress"
          ],
          "ownerOnlyInStates": [
            "in_progress"
          ],
          "requiredStepSet": "none",
          "commentRequired": true,
          "surfaces": [
            "card"
          ]
        },
        {
          "id": "mass",
          "label": "Массовый сбой",
          "permission": "incident:close:unprocessed",
          "fromStates": [
            "new",
            "pending_acceptance",
            "in_progress",
            "on_hold"
          ],
          "ownerOnlyInStates": [
            "in_progress",
            "on_hold"
          ],
          "requiredStepSet": "none",
          "commentRequired": true,
          "surfaces": [
            "queue",
            "card"
          ],
          "causeCatalog": "mass_fault"
        }
      ]
    },
    "mass_fault": {
      "$comment": "§2.2. Причина массового сбоя — уточнение к результату «Массовый сбой».",
      "field": "close_cause",
      "requiredOnTransition": [],
      "items": [
        {
          "id": "power",
          "label": "Отключение электричества на площадке",
          "setBy": "operator"
        },
        {
          "id": "link",
          "label": "Потеря связи с площадкой",
          "setBy": "operator"
        },
        {
          "id": "mass_fault",
          "label": "Массовый сбой оборудования",
          "setBy": "operator"
        },
        {
          "id": "known",
          "label": "Известная неисправность, работы ведутся",
          "setBy": "operator"
        }
      ]
    }
  },
  "stepSets": {
    "$comment": "§14.5. Наборы обязательных шагов привязаны к переходу, а не к инциденту. closing — то, что обязан заполнить оператор перед закрытием с результатом «Обработан». Состав шагов задаёт отдельная машина сценариев (§14.5), здесь только ссылка на набор.",
    "closing": {
      "id": "closing",
      "label": "Закрытие",
      "rule": "all_required_steps_answered"
    },
    "none": {
      "id": "none",
      "label": "Без проверки",
      "rule": "always_true"
    }
  },
  "forms": [
    {
      "id": "transfer",
      "title": "Передать инцидент",
      "confirmLabel": "Передать",
      "style": "warn",
      "notes": [
        {
          "when": {
            "state": "new"
          },
          "text": "Инцидент передаётся без взятия в работу. Уровень станет {nextEscalationLevel}."
        },
        {
          "when": {
            "ownership": "other"
          },
          "text": "Инцидент занят: {ownerName}. Передача другому адресату без перехвата."
        },
        {
          "when": {},
          "text": "Обработка прерывается, прогресс сценария передаётся адресату. Уровень станет {nextEscalationLevel}."
        }
      ],
      "fields": [
        {
          "name": "targetId",
          "kind": "select",
          "label": "Кому передать",
          "required": true,
          "source": "transferTargets",
          "defaultFrom": "session.preferences.defaultTransferTargetId",
          "excludes": [
            "self",
            "currentOwner",
            "noAccess",
            "cannotAccept"
          ]
        },
        {
          "name": "comment",
          "kind": "text",
          "label": "Причина",
          "required": true,
          "placeholder": "Почему передаёте"
        }
      ]
    },
    {
      "id": "hold",
      "title": "Отложить инцидент",
      "confirmLabel": "Отложить",
      "style": "primary",
      "notes": [
        {
          "when": {},
          "text": "Норматив закрытия приостанавливается и продолжится при возобновлении."
        }
      ],
      "fields": [
        {
          "name": "reasonId",
          "kind": "select",
          "label": "Причина удержания",
          "required": true,
          "source": "reasonCatalog:hold",
          "excludeSystemItems": true
        },
        {
          "name": "comment",
          "kind": "text",
          "label": "Комментарий",
          "required": false,
          "placeholder": "Чего ждём"
        }
      ]
    },
    {
      "id": "release",
      "title": "Вернуть в очередь",
      "confirmLabel": "Вернуть",
      "style": "primary",
      "notes": [
        {
          "when": {},
          "text": "Инцидент станет ничьим, норматив реакции запустится заново, норматив закрытия приостановится. Прогресс сценария сохранится."
        }
      ],
      "fields": [
        {
          "name": "comment",
          "kind": "text",
          "label": "Причина",
          "required": true,
          "placeholder": "Почему возвращаете"
        }
      ]
    },
    {
      "id": "reject",
      "title": "Отклонить передачу",
      "confirmLabel": "Отклонить",
      "style": "primary",
      "notes": [
        {
          "when": {},
          "text": "Инцидент вернётся в общую очередь, уровень эскалации сохранится."
        }
      ],
      "fields": [
        {
          "name": "comment",
          "kind": "text",
          "label": "Причина",
          "required": true,
          "placeholder": "Почему не принимаете"
        }
      ]
    },
    {
      "id": "close",
      "title": "Закрытие инцидента",
      "confirmLabel": "Закрыть инцидент",
      "style": "primary",
      "notes": [
        {
          "when": {
            "grouped": true
          },
          "text": "Сценарий заполнен: {filledSteps} из {totalSteps}. Закроются все {groupSize} инцидентов группы."
        },
        {
          "when": {},
          "text": "Сценарий заполнен: {filledSteps} из {totalSteps}. Результат уйдёт в AxxonData."
        }
      ],
      "fields": [
        {
          "name": "resultId",
          "kind": "select",
          "label": "Результат",
          "required": true,
          "source": "reasonCatalog:close_result",
          "optionsFrom": "actions",
          "defaultWhen": {
            "requiredStepsFilled": "closing",
            "value": "processed"
          },
          "placeholder": "Выберите результат",
          "$comment": "§2.2 (RULE-23). Список с placeholder пуст, пока оператор не выберет сам: случайное «Закрыть» не должно записать результат, которого он не выбирал. Значение ставится, только если его задаёт defaultWhen или вариант один"
        },
        {
          "name": "causeId",
          "kind": "select",
          "label": "Причина сбоя",
          "required": true,
          "source": "reasonCatalog:mass_fault",
          "visibleWhen": {
            "field": "resultId",
            "in": [
              "mass"
            ]
          }
        },
        {
          "name": "comment",
          "kind": "text",
          "label": "Комментарий",
          "required": false,
          "requiredFrom": "reasonCatalog:close_result.commentRequired",
          "placeholder": "Итог обработки для отчёта"
        }
      ]
    },
    {
      "id": "reopen",
      "title": "Переоткрыть инцидент",
      "confirmLabel": "Переоткрыть",
      "style": "primary",
      "notes": [
        {
          "when": {},
          "text": "Завершён {minutesSinceClose} мин назад. Норматив закрытия начнётся заново, прежние нарушения останутся."
        }
      ],
      "fields": [
        {
          "name": "comment",
          "kind": "text",
          "label": "Основание",
          "required": true,
          "placeholder": "Почему требуется вернуть в работу"
        }
      ]
    },
    {
      "id": "takeover",
      "title": "Перехватить инцидент",
      "confirmLabel": "Перехватить",
      "style": "danger",
      "notes": [
        {
          "when": {},
          "text": "Инцидент занят: {ownerName}. Прогресс сценария {filledSteps}/{totalSteps} сохранится, его карточка перейдёт в просмотр."
        }
      ],
      "fields": []
    }
  ],
  "transitions": [
    {
      "id": "claim",
      "label": "Взять",
      "labelKey": "workflow.transition.claim",
      "hint": "Взять инцидент в работу",
      "from": [
        "new"
      ],
      "to": "in_progress",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": null,
      "requiredStepSet": "none",
      "guards": [
        {
          "fn": "hasPermission",
          "args": [
            "incident:claim"
          ]
        },
        {
          "fn": "agentReady"
        },
        {
          "fn": "withinActiveLimit"
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            "actor"
          ]
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "resumeTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setCursor",
          "args": [
            "firstOpenStep"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Взято в работу"
          ]
        }
      ],
      "bulk": {
        "allowed": true,
        "mode": "same_type_new",
        "minItems": 2,
        "createsGroup": true
      },
      "ui": {
        "surface": [
          "queue"
        ],
        "style": "primary",
        "hotkey": "N",
        "navigate": "card"
      }
    },
    {
      "id": "accept",
      "label": "Принять",
      "labelKey": "workflow.transition.accept",
      "hint": "Принять адресованную вам передачу",
      "from": [
        "pending_acceptance"
      ],
      "to": "in_progress",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": null,
      "requiredStepSet": "none",
      "guards": [
        {
          "fn": "hasPermission",
          "args": [
            "incident:accept"
          ]
        },
        {
          "fn": "isTarget"
        },
        {
          "fn": "agentReady"
        },
        {
          "fn": "withinActiveLimit"
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            "actor"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "resumeTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Передача принята, прогресс сценария сохранён"
          ]
        }
      ],
      "bulk": {
        "allowed": false
      },
      "ui": {
        "surface": [
          "queue",
          "card"
        ],
        "style": "primary",
        "hotkey": "A",
        "navigate": "card"
      }
    },
    {
      "id": "reject",
      "label": "Отклонить",
      "labelKey": "workflow.transition.reject",
      "hint": "Вернуть передачу в общую очередь",
      "from": [
        "pending_acceptance"
      ],
      "to": "new",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": "reject",
      "requiredStepSet": "none",
      "guards": [
        {
          "fn": "hasPermission",
          "args": [
            "incident:release"
          ]
        },
        {
          "fn": "isTarget"
        },
        {
          "fn": "agentReady"
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Передача отклонена: {comment}"
          ]
        }
      ],
      "bulk": {
        "allowed": true,
        "mode": "each_allowed",
        "minItems": 2
      },
      "ui": {
        "surface": [
          "queue",
          "card"
        ],
        "style": "outline",
        "hotkey": null,
        "navigate": "queue"
      }
    },
    {
      "id": "hold",
      "label": "Отложить",
      "labelKey": "workflow.transition.hold",
      "hint": "Отложить с указанием причины",
      "from": [
        "in_progress"
      ],
      "to": "on_hold",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": "hold",
      "requiredStepSet": "none",
      "guards": [
        {
          "fn": "hasPermission",
          "args": [
            "incident:hold"
          ]
        },
        {
          "fn": "isOwner"
        },
        {
          "fn": "agentReady"
        },
        {
          "fn": "withinHoldLimit"
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setHoldReason",
          "args": [
            "form.reasonId"
          ]
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Отложен на шаге {stepNumber}: {holdReasonLabel}. {comment}"
          ]
        },
        {
          "kind": "transactional",
          "fn": "returnToQueue"
        }
      ],
      "bulk": {
        "allowed": true,
        "mode": "group",
        "minItems": 2
      },
      "ui": {
        "surface": [
          "card"
        ],
        "style": "outline",
        "hotkey": "H",
        "navigate": "queue"
      }
    },
    {
      "id": "resume",
      "label": "Возобновить",
      "labelKey": "workflow.transition.resume",
      "hint": "Продолжить обработку с того же остатка норматива",
      "from": [
        "on_hold"
      ],
      "to": "in_progress",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": null,
      "requiredStepSet": "none",
      "guards": [
        {
          "fn": "hasPermission",
          "args": [
            "incident:claim"
          ]
        },
        {
          "fn": "isOwner"
        },
        {
          "fn": "agentReady"
        },
        {
          "fn": "withinActiveLimit"
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "clearHoldReason"
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "resumeTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Обработка возобновлена на шаге {stepNumber}"
          ]
        }
      ],
      "bulk": {
        "allowed": false
      },
      "ui": {
        "surface": [
          "queue",
          "card"
        ],
        "style": "primary",
        "hotkey": "R",
        "navigate": "card"
      }
    },
    {
      "id": "release",
      "label": "Вернуть в очередь",
      "labelKey": "workflow.transition.release",
      "hint": "Снять с себя и вернуть инцидент в общую очередь",
      "from": [
        "in_progress",
        "on_hold"
      ],
      "to": "new",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": "release",
      "requiredStepSet": "none",
      "guards": [
        {
          "fn": "hasPermission",
          "args": [
            "incident:release"
          ]
        },
        {
          "fn": "isOwner"
        },
        {
          "fn": "agentReady"
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearHoldReason"
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearGroup"
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Возвращён в очередь: {comment}"
          ]
        },
        {
          "kind": "transactional",
          "fn": "returnToQueue"
        }
      ],
      "bulk": {
        "allowed": true,
        "mode": "group",
        "minItems": 2
      },
      "ui": {
        "surface": [
          "card"
        ],
        "style": "outline",
        "hotkey": null,
        "navigate": "queue"
      }
    },
    {
      "id": "transfer",
      "label": "Передать",
      "labelKey": "workflow.transition.transfer",
      "hint": "Передать инцидент другому адресату",
      "from": [
        "new",
        "pending_acceptance",
        "in_progress",
        "on_hold"
      ],
      "to": "pending_acceptance",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": "transfer",
      "requiredStepSet": "none",
      "guards": [
        {
          "fn": "hasScopedPermission",
          "args": [
            "incident:transfer"
          ],
          "scopeRule": {
            "own": {
              "anyOf": [
                {
                  "state": "new"
                },
                {
                  "ownership": "owner"
                },
                {
                  "ownership": "target"
                }
              ]
            },
            "any": "otherwise"
          }
        },
        {
          "fn": "agentReady"
        },
        {
          "fn": "targetIsNotSelf"
        },
        {
          "fn": "targetHasAccess"
        },
        {
          "fn": "targetCanAccept"
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            "form.targetId.ifPerson"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            "form.targetId.ifGroup"
          ]
        },
        {
          "kind": "transactional",
          "fn": "increment",
          "args": [
            "escalation_level"
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearHoldReason"
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "reaction",
            "byEscalationLevel"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Передано → {targetName} (уровень {escalationLevel}). {comment}"
          ]
        },
        {
          "kind": "transactional",
          "fn": "evictOpenCard",
          "args": [
            "previousOwner"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "previousOwner"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "newTarget"
          ]
        }
      ],
      "bulk": {
        "allowed": true,
        "mode": "each_allowed",
        "minItems": 2,
        "sharedForm": true
      },
      "ui": {
        "surface": [
          "queue",
          "card"
        ],
        "style": "warn",
        "hotkey": "E",
        "navigate": "queue"
      }
    },
    {
      "id": "takeover",
      "label": "Перехватить",
      "labelKey": "workflow.transition.takeover",
      "hint": "Забрать инцидент у работающего оператора",
      "from": [
        "pending_acceptance",
        "in_progress",
        "on_hold"
      ],
      "to": "in_progress",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": "takeover",
      "requiredStepSet": "none",
      "guards": [
        {
          "fn": "hasPermission",
          "args": [
            "incident:reassign"
          ]
        },
        {
          "fn": "hasPermission",
          "args": [
            "incident:claim"
          ]
        },
        {
          "fn": "isNotOwner"
        },
        {
          "fn": "agentReady"
        },
        {
          "fn": "withinActiveLimit"
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            "actor"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearHoldReason"
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "resumeTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Перехват у {previousOwnerName}. Прогресс сценария сохранён ({filledSteps}/{totalSteps})"
          ]
        },
        {
          "kind": "transactional",
          "fn": "evictOpenCard",
          "args": [
            "previousOwner"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "previousOwner"
          ]
        }
      ],
      "bulk": {
        "allowed": false
      },
      "ui": {
        "surface": [
          "card"
        ],
        "style": "danger",
        "hotkey": "T",
        "navigate": "card",
        "$comment": "§7. Только из карточки: оператор должен сначала увидеть, что уже сделано."
      }
    },
    {
      "id": "close",
      "label": "Закрыть",
      "labelKey": "workflow.transition.close",
      "hint": "Закрыть с результатом",
      "$comment": "§2.2, §6.1. Один переход для всех результатов (RULE-02). Откуда, по какому праву и с какими шагами — по строке справочника close_result, проверяет closeResultAllowed. /actions отдаёт в fieldOptions.resultId только доступные результаты.",
      "from": [
        "new",
        "pending_acceptance",
        "in_progress",
        "on_hold"
      ],
      "to": "closed",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": "close",
      "requiredStepSet": "byCloseResult",
      "guards": [
        {
          "fn": "agentReady"
        },
        {
          "fn": "closeResultAllowed",
          "args": [
            "form.resultId"
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            "actor"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "setFlag",
          "args": [
            "closed_by",
            "actor"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setFlag",
          "args": [
            "closed_at",
            "now"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setFlag",
          "args": [
            "close_result",
            "form.resultId"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setFlag",
          "args": [
            "close_cause",
            "form.causeId"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setFlag",
          "args": [
            "result",
            "form.comment"
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearHoldReason"
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Закрыт: {closeResultLabel}. {comment}"
          ]
        },
        {
          "kind": "transactional",
          "fn": "returnToQueue"
        },
        {
          "kind": "external",
          "fn": "externalCommand",
          "args": [
            "axxondata.export_incident"
          ]
        }
      ],
      "bulk": {
        "allowed": true,
        "mode": "group_or_each_allowed",
        "$comment": "§11. Группа сценария закрывается одним результатом на всех; ручная выборка — если выбранный результат доступен каждому.",
        "minItems": 2,
        "sharedForm": true,
        "createsGroup": false
      },
      "ui": {
        "surface": [
          "queue",
          "card"
        ],
        "style": "outline",
        "hotkey": "Enter",
        "navigate": "queue"
      }
    },
    {
      "id": "reopen",
      "label": "Переоткрыть",
      "labelKey": "workflow.transition.reopen",
      "hint": "Вернуть завершённый инцидент в работу",
      "from": [
        "closed"
      ],
      "to": "in_progress",
      "trigger": "manual",
      "concurrency": {
        "expectedVersion": true,
        "onTimerConflict": "manual_wins"
      },
      "form": "reopen",
      "requiredStepSet": "none",
      "guards": [
        {
          "fn": "hasPermission",
          "args": [
            "incident:reopen"
          ]
        },
        {
          "fn": "hasPermission",
          "args": [
            "incident:claim"
          ]
        },
        {
          "fn": "agentReady"
        },
        {
          "fn": "withinReopenWindow"
        },
        {
          "fn": "withinActiveLimit"
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            "actor"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setFlag",
          "args": [
            "close_result",
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "setFlag",
          "args": [
            "close_cause",
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "restartTimer",
          "args": [
            "resolution",
            "limits.reopenResolutionSec"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Переоткрыт после закрытия ({closeResultLabel}): {comment}"
          ]
        }
      ],
      "bulk": {
        "allowed": false
      },
      "ui": {
        "surface": [
          "queue",
          "card"
        ],
        "style": "outline",
        "hotkey": null,
        "navigate": "card"
      }
    },
    {
      "id": "auto_escalate",
      "label": "Автоэскалация",
      "from": [
        "new",
        "pending_acceptance"
      ],
      "to": "pending_acceptance",
      "trigger": "timer",
      "actor": "dispatcher",
      "guards": [
        {
          "fn": "settingEnabled",
          "args": [
            "escalation.enabled"
          ]
        },
        {
          "fn": "timerExpired",
          "args": [
            "reaction"
          ]
        },
        {
          "fn": "escalationTargetAvailable",
          "args": [
            true
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            "escalation.level.target.ifPerson"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            "escalation.level.target.ifGroup"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setFlag",
          "args": [
            "escalation_level",
            "escalation.level.number"
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearHoldReason"
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "reaction",
            "escalation.level.reactionSec"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Автоэскалация → {targetName} (уровень {escalationLevel}). {escalationReason}"
          ]
        },
        {
          "kind": "transactional",
          "fn": "evictOpenCard",
          "args": [
            "previousOwner"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "newTarget"
          ]
        }
      ],
      "ui": {
        "surface": [],
        "style": null,
        "hotkey": null,
        "navigate": null
      }
    },
    {
      "id": "escalation_ceiling",
      "label": "Эскалировать некому",
      "from": [
        "new",
        "pending_acceptance"
      ],
      "to": null,
      "trigger": "timer",
      "actor": "dispatcher",
      "guards": [
        {
          "fn": "settingEnabled",
          "args": [
            "escalation.enabled"
          ]
        },
        {
          "fn": "timerExpired",
          "args": [
            "reaction"
          ]
        },
        {
          "fn": "escalationTargetAvailable",
          "args": [
            false
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "recordBreach",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Эскалировать некому: норматив реакции нарушен, алерт получателю"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "alerts.target"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "reaction_overdue",
      "label": "Норматив реакции нарушен",
      "$comment": "§4, §9 (RULE-40). Автоэскалация выключена: истёкшая реакция — нарушение и алерт получателю алертов, без передачи. Иначе просрочка реакции не оставила бы следа ни в журнале, ни в отчётах.",
      "from": [
        "new",
        "pending_acceptance"
      ],
      "to": null,
      "trigger": "timer",
      "actor": "dispatcher",
      "guards": [
        {
          "fn": "settingIs",
          "args": [
            "escalation.enabled",
            false
          ]
        },
        {
          "fn": "timerExpired",
          "args": [
            "reaction"
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "recordBreach",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Норматив реакции нарушен, алерт получателю"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "alerts.target"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "resolution_overdue",
      "label": "Норматив закрытия нарушен",
      "from": [
        "in_progress"
      ],
      "to": null,
      "trigger": "timer",
      "actor": "dispatcher",
      "guards": [
        {
          "fn": "timerExpired",
          "args": [
            "resolution"
          ]
        },
        {
          "fn": "settingIs",
          "args": [
            "escalation.onResolutionOverdue",
            "alert"
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "recordBreach",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Норматив закрытия нарушен, алерт получателю"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "alerts.target"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "resolution_escalate",
      "label": "Эскалация по нормативу закрытия",
      "$comment": "§4, правило 4; §9 (RULE-27). Включается настройкой escalation.onResolutionOverdue = escalate: истёк норматив закрытия — нарушение и передача адресату следующего уровня, как автоэскалация по реакции. Три перехода по этому таймеру — алерт, эскалация, потолок — взаимоисключающие по условиям.",
      "from": [
        "in_progress"
      ],
      "to": "pending_acceptance",
      "trigger": "timer",
      "actor": "dispatcher",
      "guards": [
        {
          "fn": "settingIs",
          "args": [
            "escalation.onResolutionOverdue",
            "escalate"
          ]
        },
        {
          "fn": "timerExpired",
          "args": [
            "resolution"
          ]
        },
        {
          "fn": "escalationTargetAvailable",
          "args": [
            true
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "recordBreach",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            "escalation.level.target.ifPerson"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            "escalation.level.target.ifGroup"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setFlag",
          "args": [
            "escalation_level",
            "escalation.level.number"
          ]
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "reaction",
            "escalation.level.reactionSec"
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearGroup"
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Норматив закрытия нарушен, эскалация → {targetName} (уровень {escalationLevel})"
          ]
        },
        {
          "kind": "transactional",
          "fn": "evictOpenCard",
          "args": [
            "previousOwner"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "previousOwner"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "newTarget"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "resolution_ceiling",
      "label": "Норматив закрытия нарушен, эскалировать некому",
      "$comment": "§9 (RULE-27). Эскалация по нормативу закрытия включена, но уровень уже на потолке: нарушение и алерт получателю алертов, состояние не меняется.",
      "from": [
        "in_progress"
      ],
      "to": null,
      "trigger": "timer",
      "actor": "dispatcher",
      "guards": [
        {
          "fn": "settingIs",
          "args": [
            "escalation.onResolutionOverdue",
            "escalate"
          ]
        },
        {
          "fn": "timerExpired",
          "args": [
            "resolution"
          ]
        },
        {
          "fn": "escalationTargetAvailable",
          "args": [
            false
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "recordBreach",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Норматив закрытия нарушен, эскалировать некому: алерт получателю"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "alerts.target"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "hold_overdue",
      "label": "Предельный срок удержания истёк",
      "from": [
        "on_hold"
      ],
      "to": null,
      "trigger": "timer",
      "actor": "dispatcher",
      "guards": [
        {
          "fn": "timerExpired",
          "args": [
            "hold"
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "recordBreach",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Предельный срок удержания «{holdReasonLabel}» истёк, алерт получателю"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "alerts.target"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "system_hold_break",
      "label": "Отложен: перерыв оператора",
      "from": [
        "in_progress"
      ],
      "to": "on_hold",
      "trigger": "system",
      "actor": "system",
      "scope": "incidents_owned_by_agent",
      "guards": [
        {
          "fn": "agentStateIs",
          "args": [
            "not_ready"
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setHoldReason",
          "args": [
            "break"
          ]
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Отложен системой: {holdReasonLabel}"
          ]
        },
        {
          "kind": "transactional",
          "fn": "evictOpenCard",
          "args": [
            "owner"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "system_hold_idle",
      "label": "Отложен: нет связи с оператором",
      "from": [
        "in_progress"
      ],
      "to": "on_hold",
      "trigger": "system",
      "scope": "incidents_owned_by_agent",
      "actor": "system",
      "guards": [
        {
          "fn": "agentIdleFor",
          "args": [
            "session.idleHoldSec"
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setHoldReason",
          "args": [
            "no_link"
          ]
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Отложен системой: нет связи с оператором"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "alerts.target"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "system_release_idle",
      "label": "Возвращён в очередь: оператор не отвечает",
      "from": [
        "on_hold"
      ],
      "to": "new",
      "trigger": "system",
      "scope": "incidents_owned_by_agent",
      "actor": "system",
      "guards": [
        {
          "fn": "agentIdleFor",
          "args": [
            "session.idleReleaseSec"
          ]
        },
        {
          "fn": "holdReasonIn",
          "args": [
            [
              "break",
              "no_link"
            ]
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearHoldReason"
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Возвращён в очередь: оператор не отвечает"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "addressee_signed_out_to_group",
      "label": "Адресат вышел: передано его дежурной группе",
      "$comment": "§8.1 (RULE-28, RULE-37). Адресованный лично и не принятый инцидент уходит дежурной группе адресата, когда тот выходит из МИ. Норматив реакции продолжается: уход адресата не даёт лишнего времени. Уровень эскалации не меняется.",
      "from": [
        "pending_acceptance"
      ],
      "to": "pending_acceptance",
      "trigger": "system",
      "scope": "incidents_owned_by_agent",
      "actor": "system",
      "guards": [
        {
          "fn": "agentStateIs",
          "args": [
            "offline"
          ]
        },
        {
          "fn": "ownerHasDutyGroup",
          "args": [
            true
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            "owner.dutyGroup"
          ]
        },
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Адресат вышел, не приняв: передано группе {targetName}"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "newTarget"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "addressee_signed_out_to_queue",
      "label": "Адресат вышел: возвращён в очередь",
      "$comment": "§8.1 (RULE-28, RULE-37). У адресата нет дежурной группы — инцидент возвращается в общую очередь ничейным. Норматив реакции продолжается.",
      "from": [
        "pending_acceptance"
      ],
      "to": "new",
      "trigger": "system",
      "scope": "incidents_owned_by_agent",
      "actor": "system",
      "guards": [
        {
          "fn": "agentStateIs",
          "args": [
            "offline"
          ]
        },
        {
          "fn": "ownerHasDutyGroup",
          "args": [
            false
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Адресат вышел, не приняв: возвращён в очередь"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "owner_signed_out",
      "label": "Оператор вышел: возвращён в очередь",
      "$comment": "§12.1 (RULE-37). Оператор вышел из МИ — его инциденты в работе и отложенные, с любой причиной, сразу возвращаются в общую очередь, как по «Вернуть в очередь»: ждать срабатывания потери связи (§12.3) незачем, он ушёл сам. Уровень эскалации не меняется, прогресс сценария сохраняется.",
      "from": [
        "in_progress",
        "on_hold"
      ],
      "to": "new",
      "trigger": "system",
      "scope": "incidents_owned_by_agent",
      "actor": "system",
      "guards": [
        {
          "fn": "agentStateIs",
          "args": [
            "offline"
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearHoldReason"
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearGroup"
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Возвращён в очередь: оператор вышел"
          ]
        },
        {
          "kind": "transactional",
          "fn": "evictOpenCard",
          "args": [
            "previousOwner"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "addressee_lost_access",
      "label": "Возвращён в очередь: у владельца или адресата нет доступа к объекту",
      "$comment": "§5, §6.2 (RULE-33). Группы доступа или роли изменились, и у владельца или адресата больше нет доступа к объекту инцидента — инцидент ему не виден, поэтому возвращается в очередь. Группе-адресату хватает доступа у одного участника. Уровень эскалации не меняется, прогресс сценария сохраняется.",
      "from": [
        "pending_acceptance",
        "in_progress",
        "on_hold"
      ],
      "to": "new",
      "trigger": "system",
      "actor": "system",
      "guards": [
        {
          "fn": "addresseeHasAccess",
          "args": [
            false
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearHoldReason"
        },
        {
          "kind": "transactional",
          "fn": "stopTimer",
          "args": [
            "hold"
          ]
        },
        {
          "kind": "transactional",
          "fn": "pauseTimer",
          "args": [
            "resolution"
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "clearGroup"
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Возвращён в очередь: у {previousOwnerName} нет доступа к объекту"
          ]
        },
        {
          "kind": "transactional",
          "fn": "evictOpenCard",
          "args": [
            "previousOwner"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "alerts.target"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    },
    {
      "id": "addressee_cannot_accept",
      "label": "Возвращён в очередь: адресат не может принять",
      "$comment": "§5, §8.1 (RULE-39). Права адресата изменились: доступ к объекту есть, а права «Принимать» больше нет — у группы-адресата ни у одного участника нет того и другого. Инцидент ждал бы до истечения норматива реакции, поэтому возвращается в очередь, как при потере доступа. Касается только «Ожидает принятия»: в работе право принять уже не нужно. Без доступа срабатывает addressee_lost_access.",
      "from": [
        "pending_acceptance"
      ],
      "to": "new",
      "trigger": "system",
      "actor": "system",
      "guards": [
        {
          "fn": "addresseeHasAccess",
          "args": [
            true
          ]
        },
        {
          "fn": "addresseeCanAccept",
          "args": [
            false
          ]
        }
      ],
      "effects": [
        {
          "kind": "transactional",
          "fn": "setOwner",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "setAssignmentGroup",
          "args": [
            null
          ]
        },
        {
          "kind": "transactional",
          "fn": "startTimer",
          "args": [
            "reaction"
          ]
        },
        {
          "kind": "transactional",
          "fn": "appendLog",
          "args": [
            "Возвращён в очередь: {previousOwnerName} не может принять"
          ]
        },
        {
          "kind": "transactional",
          "fn": "evictOpenCard",
          "args": [
            "previousOwner"
          ]
        },
        {
          "kind": "external",
          "fn": "notify",
          "args": [
            "alerts.target"
          ]
        }
      ],
      "ui": {
        "surface": []
      }
    }
  ],
  "navActions": {
    "$comment": "§6.3. Не переходы: состояние и владелец не меняются. Кнопки очереди/карточки всё равно приходят с сервера вместе с переходами.",
    "items": [
      {
        "id": "open_card",
        "label": "Продолжить",
        "hint": "Вернуться к своей карточке",
        "style": "primary",
        "guards": [
          {
            "fn": "stateIs",
            "args": [
              [
                "in_progress"
              ]
            ]
          },
          {
            "fn": "isOwner"
          }
        ],
        "surface": [
          "queue"
        ],
        "$comment": "§7. Только у своего «В работе»: у отложенного — «Возобновить», это переход."
      },
      {
        "id": "open_readonly",
        "label": "Открыть",
        "hint": "Просмотр без изменений",
        "style": "outline",
        "guards": [
          {
            "fn": "stateIs",
            "args": [
              [
                "pending_acceptance",
                "in_progress",
                "on_hold"
              ]
            ]
          },
          {
            "fn": "isNotOwner"
          },
          {
            "fn": "isNotTarget"
          },
          {
            "fn": "hasPermission",
            "args": [
              "incident:read:any"
            ]
          }
        ],
        "surface": [
          "queue"
        ],
        "$comment": "§6.3. Чужой инцидент в работе или ожидающий принятия у другого: только просмотр."
      },
      {
        "id": "open_done",
        "label": "Просмотр",
        "hint": "Открыть карточку завершённого инцидента",
        "style": "outline",
        "guards": [
          {
            "fn": "stateIs",
            "args": [
              [
                "closed"
              ]
            ]
          },
          {
            "fn": "canReadDone"
          }
        ],
        "surface": [
          "queue"
        ]
      },
      {
        "id": "back_to_queue",
        "label": "К очереди",
        "style": "ghost",
        "guards": [],
        "surface": [
          "card"
        ]
      },
      {
        "id": "run_macro",
        "label": "Запустить макрос",
        "style": "outline",
        "guards": [
          {
            "fn": "hasPermission",
            "args": [
              "incident:run_action"
            ]
          },
          {
            "fn": "isOwner"
          },
          {
            "fn": "agentReady"
          },
          {
            "fn": "stateIs",
            "args": [
              "in_progress"
            ]
          }
        ],
        "surface": [
          "card"
        ]
      }
    ]
  },
  "escalation": {
    "$comment": "§9. Настройки под правом incident:schema:admin. Адресат уровня — пользователь или дежурная группа (§8.3). Значения ниже — пример. Адресат-группа удобнее: её состав задают роли, и при смене людей схему менять не нужно.",
    "enabled": true,
    "levels": [
      {
        "level": 1,
        "targetRef": "user:petrova",
        "reactionSec": 120
      },
      {
        "level": 2,
        "targetRef": "user:noc",
        "reactionSec": 90
      }
    ],
    "maxLevel": 2,
    "onResolutionOverdue": "alert",
    "reason": "Автоэскалация: превышен норматив реакции"
  },
  "alerts": {
    "$comment": "§9 (RULE-43). Получатель алертов — нарушения нормативов, потолок эскалации, потеря связи, потеря доступа: пользователь user:… или дежурная группа group:…; группе — всем участникам на месте. Алерт получают только те, у кого есть доступ к объекту инцидента (§5); если таких нет, нарушение и запись перехода остаются, а в журнал пишется noRecipientLog. Алерт не передаёт инцидент и не меняет владельца. Настройка под правом incident:schema:admin.",
    "target": "group:grp-leads",
    "noRecipientLog": "Алерт не отправлен: получателя на месте с доступом к объекту нет"
  },
  "limits": {
    "$comment": "§10.2, §11. Инциденты одной группы считаются одной единицей, иначе групповая обработка упиралась бы в лимит активных. maxOnHold проверяет только ручное «Отложить» (withinHoldLimit у hold); системные удержания system_hold_* откладывают всегда.",
    "maxActive": 1,
    "maxOnHold": 5,
    "maxBulk": 10,
    "reopenWindowMin": 1440,
    "reopenResolutionSec": null,
    "groupCountsAsOneUnit": true
  },
  "scenarioEdit": {
    "$comment": "§10.4. Кто может править шаги сценария и отвечать на них (PATCH .../scenario/answers, PUT .../scenario/cursor). Не выполнено — карточка открыта на просмотр (IncidentCard.readOnly). Макросы — по своим условиям: navActions.run_macro.",
    "guards": [
      {
        "fn": "stateIs",
        "args": [
          [
            "in_progress"
          ]
        ]
      },
      {
        "fn": "isOwner"
      },
      {
        "fn": "agentReady"
      }
    ]
  },
  "grouping": {
    "$comment": "§11. Группа — признак (group_id), а не сущность: родительский инцидент не создаётся.",
    "enabled": true,
    "permissions": [
      "incident:bulk",
      "incident:claim"
    ],
    "createFrom": {
      "states": [
        "new"
      ],
      "sameEventType": true,
      "minItems": 2,
      "maxItems": 10
    },
    "shared": [
      "group_id",
      "owner",
      "scenarioAnswers"
    ],
    "notShared": [
      "state",
      "timers",
      "journal"
    ],
    "memberLeavesGroupOn": [
      "manual_exclude"
    ],
    "excludeGuards": [
      {
        "fn": "stateIs",
        "args": [
          [
            "in_progress"
          ]
        ]
      },
      {
        "fn": "isOwner"
      },
      {
        "fn": "agentReady"
      },
      {
        "fn": "withinActiveLimit",
        "args": [
          1
        ],
        "$comment": "§10.2, RULE-13: исключённый инцидент остаётся в работе отдельной единицей — лимит должен это позволять"
      }
    ],
    "selectionHelpers": [
      {
        "id": "select_all",
        "label": "Выбрать все",
        "scope": "current_filter",
        "limit": "maxBulk"
      },
      {
        "id": "select_same_type",
        "label": "Однотипные",
        "scope": "state:new + same_event_type",
        "hotkey": "Shift+A"
      },
      {
        "id": "clear_selection",
        "label": "Снять",
        "hotkey": "Shift+D"
      }
    ]
  },
  "session": {
    "$comment": "§12. Состояние оператора — отдельная машина состояний, к инциденту не относится. readOnly — в этом состоянии доступен только просмотр: переходы отклоняет условие agentReady с текстом readOnlyReason.",
    "states": [
      {
        "id": "ready",
        "label": "Готов",
        "assignsNewIncidents": true
      },
      {
        "id": "busy",
        "label": "Занят",
        "assignsNewIncidents": true,
        "derived": true
      },
      {
        "id": "not_ready",
        "label": "Перерыв",
        "assignsNewIncidents": false,
        "requiresReason": true,
        "permission": "agent:set_not_ready",
        "readOnly": true,
        "readOnlyReason": "На перерыве доступен только просмотр"
      },
      {
        "id": "offline",
        "label": "Вышел",
        "assignsNewIncidents": false,
        "readOnly": true,
        "readOnlyReason": "Вы вышли из МИ: доступен только просмотр"
      }
    ],
    "breakReasons": [
      {
        "id": "lunch",
        "label": "Обед"
      },
      {
        "id": "briefing",
        "label": "Инструктаж"
      },
      {
        "id": "patrol",
        "label": "Обход"
      }
    ],
    "heartbeatSec": 30,
    "idleHoldSec": 300,
    "idleReleaseSec": 1200
  },
  "hotkeys": [
    {
      "key": "N",
      "action": "transition:claim",
      "label": "Взять следующее новое",
      "scope": "next_new",
      "worksInInput": false
    },
    {
      "key": "A",
      "action": "transition:accept",
      "label": "Принять адресованную передачу",
      "worksInInput": false
    },
    {
      "key": "R",
      "action": "transition:resume",
      "label": "Возобновить свой отложенный",
      "worksInInput": false
    },
    {
      "key": "E",
      "action": "transition:transfer",
      "label": "Передать выбранный",
      "worksInInput": false
    },
    {
      "key": "T",
      "action": "transition:takeover",
      "label": "Перехватить (по праву, из карточки)",
      "worksInInput": false
    },
    {
      "key": "H",
      "action": "transition:hold",
      "label": "Отложить с указанием причины",
      "worksInInput": false
    },
    {
      "key": "G",
      "action": "group:create",
      "label": "Обработать выделенные как одно",
      "worksInInput": false
    },
    {
      "key": "Shift+A",
      "action": "selection:same_type",
      "label": "Выбрать однотипные",
      "worksInInput": false
    },
    {
      "key": "Shift+D",
      "action": "selection:clear",
      "label": "Снять выделение",
      "worksInInput": false
    },
    {
      "key": "B",
      "action": "session:toggle_break",
      "label": "Перерыв / возврат с перерыва",
      "worksInInput": false
    },
    {
      "key": "Enter",
      "action": "form:open:close",
      "label": "Открыть форму закрытия инцидента",
      "worksInInput": false
    },
    {
      "key": "ArrowLeft",
      "action": "media:camera_prev",
      "label": "Карусель камер",
      "worksInInput": false
    },
    {
      "key": "ArrowRight",
      "action": "media:camera_next",
      "label": "Карусель камер",
      "worksInInput": false
    },
    {
      "key": "1",
      "action": "media:camera_select",
      "label": "Камера по номеру",
      "args": [
        1
      ],
      "worksInInput": false
    },
    {
      "key": "2",
      "action": "media:camera_select",
      "label": "Камера по номеру",
      "args": [
        2
      ],
      "worksInInput": false
    },
    {
      "key": "3",
      "action": "media:camera_select",
      "label": "Камера по номеру",
      "args": [
        3
      ],
      "worksInInput": false
    },
    {
      "key": "4",
      "action": "media:camera_select",
      "label": "Камера по номеру",
      "args": [
        4
      ],
      "worksInInput": false
    },
    {
      "key": "F1",
      "action": "docs:regulation",
      "label": "Регламент обработки инцидента — из любого места",
      "worksInInput": true,
      "worksInModal": true,
      "reassignable": false
    },
    {
      "key": "?",
      "action": "docs:hotkeys",
      "label": "Эта справка",
      "worksInInput": false,
      "worksInModal": true,
      "reassignable": false
    },
    {
      "key": "Esc",
      "action": "escape_chain",
      "label": "Форма → полный экран → панель групп → возврат к очереди",
      "worksInInput": true,
      "worksInModal": true,
      "reassignable": false,
      "chain": [
        "close_form",
        "exit_fullscreen",
        "close_groups_panel",
        "back_to_queue"
      ]
    }
  ],
  "queueFilters": [
    {
      "id": "open",
      "label": "Открытые",
      "stateCategories": [
        "pending",
        "active"
      ]
    },
    {
      "id": "inbox",
      "label": "Мне на принятие",
      "states": [
        "pending_acceptance"
      ],
      "ownership": "target"
    },
    {
      "id": "mine",
      "label": "Мои",
      "states": [
        "in_progress",
        "on_hold"
      ],
      "ownership": "owner"
    },
    {
      "id": "foreign",
      "label": "Чужие",
      "states": [
        "pending_acceptance",
        "in_progress",
        "on_hold"
      ],
      "ownership": "other"
    },
    {
      "id": "done",
      "label": "Завершённые",
      "stateCategories": [
        "done"
      ]
    },
    {
      "id": "all",
      "label": "Все"
    }
  ],
  "queueGrouping": {
    "$comment": "§19 (RULE-03). Четыре режима группировки из Vision покрываются двумя механизмами. Регион и свой список — группы устройств: вложенные, одно устройство может входить в несколько групп; выбранная группа ограничивает очередь событиями её устройств, включая вложенные группы. Тип события и тип устройства-источника — фильтры очереди поверх выбранной группы. Дерево групп отдаёт GET /operator/reference/source-groups.",
    "groups": {
      "nested": true,
      "deviceInManyGroups": true,
      "selectionIncludesNested": true
    },
    "filters": [
      {
        "id": "eventType",
        "label": "Тип события",
        "field": "eventType"
      },
      {
        "id": "deviceType",
        "label": "Тип устройства",
        "field": "source.typeId"
      }
    ]
  },
  "registries": {
    "$comment": "§14.8. Фиксированные реестры: продуктовая команда собирает схему из этих функций, разработчики расширяют сами реестры. Отмеченные extendsBaseRegistry добавлены в v4 сверх списка из §14.8 — их нужно реализовать.",
    "guards": [
      {
        "fn": "hasPermission",
        "args": [
          "permissionKey"
        ],
        "onFail": "hide"
      },
      {
        "fn": "hasScopedPermission",
        "args": [
          "resourceAction"
        ],
        "onFail": "hide",
        "extendsBaseRegistry": true
      },
      {
        "fn": "isOwner",
        "args": [],
        "onFail": "hide"
      },
      {
        "fn": "isNotOwner",
        "args": [],
        "onFail": "hide",
        "extendsBaseRegistry": true
      },
      {
        "fn": "isTarget",
        "args": [],
        "onFail": "hide"
      },
      {
        "fn": "isNotTarget",
        "args": [],
        "onFail": "hide",
        "extendsBaseRegistry": true
      },
      {
        "fn": "targetIsNotSelf",
        "args": [],
        "onFail": "disable",
        "extendsBaseRegistry": true
      },
      {
        "fn": "targetCanAccept",
        "args": [],
        "onFail": "disable",
        "extendsBaseRegistry": true,
        "$comment": "§8.1. Адресат из формы может принять: у человека — право incident:accept и доступ к объекту, у дежурной группы — хотя бы один участник с тем и другим."
      },
      {
        "fn": "targetHasAccess",
        "args": [],
        "onFail": "disable",
        "extendsBaseRegistry": true,
        "$comment": "§8.1. Адресату из формы доступно устройство-источник инцидента: человеку — по группам доступа его ролей, дежурной группе — хотя бы одному участнику (§5)."
      },
      {
        "fn": "agentReady",
        "args": [],
        "onFail": "disable"
      },
      {
        "fn": "agentStateIs",
        "args": [
          "agentState"
        ],
        "onFail": "disable",
        "extendsBaseRegistry": true
      },
      {
        "fn": "agentIdleFor",
        "args": [
          "seconds"
        ],
        "onFail": "disable",
        "extendsBaseRegistry": true
      },
      {
        "fn": "addresseeHasAccess",
        "args": [
          "expected"
        ],
        "onFail": "hide",
        "extendsBaseRegistry": true,
        "$comment": "§5. Есть ли у владельца или адресата инцидента доступ к его объекту: человеку — по ролям, группе-адресату — хотя бы у одного участника. Инцидент без адресата условию false не отвечает."
      },
      {
        "fn": "addresseeCanAccept",
        "args": [
          "expected"
        ],
        "onFail": "hide",
        "extendsBaseRegistry": true,
        "$comment": "§8.1. Может ли владелец или адресат инцидента принять: право incident:accept и доступ к объекту; группе-адресату — хотя бы у одного участника и то, и другое. Инцидент без адресата условию false не отвечает."
      },
      {
        "fn": "ownerHasDutyGroup",
        "args": [
          "expected"
        ],
        "onFail": "hide",
        "extendsBaseRegistry": true,
        "$comment": "§8.1. Состоит ли владелец-человек в дежурной группе: true — да, false — нет. Его группа — значение owner.dutyGroup в эффектах."
      },
      {
        "fn": "withinActiveLimit",
        "args": [
          "extraUnits?"
        ],
        "onFail": "disable",
        "$comment": "§10.2. Сколько единиц уже в работе, не считая единицы самого инцидента (группа — одна единица). extraUnits — сколько единиц добавит действие сверх неё: исключение из группы делает её двумя (RULE-13)."
      },
      {
        "fn": "withinHoldLimit",
        "args": [],
        "onFail": "disable",
        "extendsBaseRegistry": true
      },
      {
        "fn": "withinReopenWindow",
        "args": [],
        "onFail": "hide",
        "extendsBaseRegistry": true
      },
      {
        "fn": "requiredStepsFilled",
        "args": [
          "stepSetId"
        ],
        "onFail": "disable"
      },
      {
        "fn": "closeResultAllowed",
        "args": [
          "resultId"
        ],
        "onFail": "hide",
        "extendsBaseRegistry": true,
        "$comment": "§2.2. Есть ли у результата право, подходит ли состояние и владение, заполнены ли шаги его набора. Без resultId — доступен ли хоть один результат: так решается, показывать ли кнопку."
      },
      {
        "fn": "timerExpired",
        "args": [
          "timerId"
        ],
        "onFail": "hide",
        "$comment": "§14.3. Дедлайн наступил и ещё не сработал: каждый дедлайн срабатывает один раз, как у планировщика на сервере. Новый дедлайн того же таймера — новое срабатывание."
      },
      {
        "fn": "escalationTargetAvailable",
        "args": [
          "expected"
        ],
        "onFail": "hide",
        "extendsBaseRegistry": true,
        "$comment": "§8.3. Есть ли следующий уровень эскалации не выше потолка, у адресата которого есть доступ к объекту инцидента (§5): true — есть, false — нет: инцидент никому не передаётся, записывается нарушение и уходит алерт ответственному (escalation_ceiling, resolution_ceiling). Уровни без доступа пропускаются; найденный уровень — значения escalation.level.target и escalation.level.number в эффектах."
      },
      {
        "fn": "holdReasonIn",
        "args": [
          "reasonIds"
        ],
        "onFail": "hide",
        "extendsBaseRegistry": true
      },
      {
        "fn": "stateIs",
        "args": [
          "stateIds"
        ],
        "onFail": "hide",
        "extendsBaseRegistry": true
      },
      {
        "fn": "canReadDone",
        "args": [],
        "onFail": "hide",
        "extendsBaseRegistry": true
      },
      {
        "fn": "settingEnabled",
        "args": [
          "settingKey"
        ],
        "onFail": "hide"
      },
      {
        "fn": "settingIs",
        "args": [
          "settingKey",
          "value"
        ],
        "onFail": "hide",
        "extendsBaseRegistry": true,
        "$comment": "Настройка схемы равна значению: например, escalation.onResolutionOverdue — alert или escalate (§9)."
      }
    ],
    "effects": [
      {
        "fn": "setOwner",
        "kind": "transactional"
      },
      {
        "fn": "setAssignmentGroup",
        "kind": "transactional"
      },
      {
        "fn": "setHoldReason",
        "kind": "transactional"
      },
      {
        "fn": "clearHoldReason",
        "kind": "transactional"
      },
      {
        "fn": "startTimer",
        "kind": "transactional"
      },
      {
        "fn": "stopTimer",
        "kind": "transactional"
      },
      {
        "fn": "pauseTimer",
        "kind": "transactional"
      },
      {
        "fn": "restartTimer",
        "kind": "transactional",
        "extendsBaseRegistry": true,
        "$comment": "§4, правило 6 (RULE-11). Запускает таймер заново, без остатка. Второй аргумент — путь к настройке длительности; не задана (null) — обычный норматив по §4. Переоткрытие запускает так норматив закрытия."
      },
      {
        "fn": "recordBreach",
        "kind": "transactional",
        "extendsBaseRegistry": true,
        "$comment": "§2.2 (RULE-12). Дописывает в breaches запись: вид нарушения (reaction / resolution / hold), когда, чей — владелец в этот момент. sla_breached — есть хоть одна запись. Записи не стираются, в том числе при переоткрытии."
      },
      {
        "fn": "resumeTimer",
        "kind": "transactional",
        "$comment": "§14.8. Продолжает таймер с остатка; ещё не запускавшийся — запускает с полного норматива. Поэтому claim, accept и reopen используют один эффект."
      },
      {
        "fn": "increment",
        "kind": "transactional"
      },
      {
        "fn": "setFlag",
        "kind": "transactional"
      },
      {
        "fn": "appendLog",
        "kind": "transactional"
      },
      {
        "fn": "returnToQueue",
        "kind": "transactional"
      },
      {
        "fn": "evictOpenCard",
        "kind": "transactional",
        "$comment": "§9, §14.8. Открытая у человека карточка переходит в режим просмотра с уведомлением (incident.card_evicted в потоке); карточка не закрывается."
      },
      {
        "fn": "setCursor",
        "kind": "transactional",
        "extendsBaseRegistry": true
      },
      {
        "fn": "clearGroup",
        "kind": "transactional",
        "extendsBaseRegistry": true
      },
      {
        "fn": "notify",
        "kind": "external"
      },
      {
        "fn": "externalCommand",
        "kind": "external"
      }
    ]
  },
  "validation": {
    "$comment": "§14.7. Проверки при сохранении схемы. Бэкенд обязан выполнять их до публикации. Что разрешают роли, МИ не знает (§5, RULE-01): проверки, зависящие от прав, идут на типовых наборах прав из typicalPermissionSets.",
    "rules": [
      "unreachable_state",
      "non_terminal_state_without_outgoing",
      "state_without_incoming",
      "permission_set_state_without_any_transition",
      "target_permission_set_cannot_exit_state",
      "duplicate_hotkey",
      "unknown_permission_reference",
      "unused_permission"
    ],
    "typicalPermissionSets": {
      "$comment": "§14.7. Примеры наборов прав для валидатора и симулятора. Это не роли: настоящие роли и их состав настраиваются во внешней системе.",
      "items": [
        {
          "id": "operator",
          "label": "Оператор",
          "permissions": [
            "incident:claim",
            "incident:accept",
            "incident:hold",
            "incident:release",
            "incident:close",
            "incident:transfer:own",
            "incident:read:any",
            "incident:bulk",
            "incident:run_action",
            "agent:set_not_ready"
          ]
        },
        {
          "id": "senior",
          "label": "Старший оператор",
          "permissions": [
            "incident:claim",
            "incident:accept",
            "incident:hold",
            "incident:release",
            "incident:close",
            "incident:close:unprocessed",
            "incident:reopen",
            "incident:transfer:own",
            "incident:transfer:any",
            "incident:reassign",
            "incident:read:any",
            "incident:bulk",
            "incident:run_action",
            "agent:set_not_ready"
          ]
        }
      ]
    },
    "claimWithoutExitPermission": {
      "$comment": "§10.3. Требование к набору прав пользователя: с incident:claim нужен хотя бы один выход из карточки. Роли собираются во внешней системе, поэтому проверяется не при публикации схемы, а при входе: если выхода нет, incident:claim не действует, администратору уходит предупреждение. Требование передаётся внешней системе вместе с каталогом прав.",
      "checkedOn": "session_start",
      "requiresAnyOf": [
        "incident:hold",
        "incident:release",
        "incident:close"
      ]
    }
  },
  "adminSettings": {
    "$comment": "RULE-44. Что настраивает администратор (право incident:schema:admin) — вкладки будущей админки. Настройка — значение, которое подстраивают под площадку, не меняя логику переходов; переходы, состояния, формы и бейджи — модель, а не настройки. path — где значение в этой машине (у списка — по id элемента); source — запрос, которым читаются данные МИ, которых в схеме нет. Из раздела собирается SETTINGS.md (tools/build_workflow.py), по нему рисуется экран настроек прототипа; check_machine.py проверяет, что пути существуют и что каждый ключ разделов-настроек либо в перечне, либо в notSettings с причиной.",
    "sections": [
      "timers",
      "reasonCatalogs",
      "escalation",
      "alerts",
      "limits",
      "session",
      "hotkeys"
    ],
    "valueLabels": {
      "$comment": "Подписи машинных значений в перечне настроек (BUG-26): приоритеты и условия уточнений нормативов. values у настройки — подписи значений её перечня.",
      "critical": "критический",
      "high": "высокий",
      "medium": "средний",
      "low": "низкий",
      "priority": "приоритет",
      "eventType": "тип события",
      "sourceGroup": "группа устройств"
    },
    "tabs": [
      {
        "id": "norms",
        "label": "Нормативы",
        "rules": "§4",
        "items": [
          {
            "path": "timers.reaction.defaultSec",
            "label": "Реакция по умолчанию",
            "what": "Сколько ждать взятия в работу, если не задано точнее"
          },
          {
            "path": "timers.reaction.overrides",
            "label": "Реакция: уточнения",
            "what": "Норматив реакции по типу события, приоритету и группе устройств; самая точная строка важнее"
          },
          {
            "path": "timers.resolution.defaultSec",
            "label": "Закрытие по умолчанию",
            "what": "Сколько можно вести инцидент от первого взятия до закрытия"
          },
          {
            "path": "timers.resolution.byPriority",
            "label": "Закрытие по приоритету",
            "what": "Норматив закрытия для каждого приоритета"
          },
          {
            "path": "timers.resolution.overrides",
            "label": "Закрытие: уточнения",
            "what": "Норматив закрытия по типу события, приоритету и группе устройств"
          },
          {
            "path": "limits.reopenWindowMin",
            "label": "Срок переоткрытия",
            "what": "Сколько после закрытия инцидент можно переоткрыть (§6.1)"
          },
          {
            "path": "limits.reopenResolutionSec",
            "label": "Закрытие после переоткрытия",
            "what": "Норматив закрытия переоткрытого инцидента; пусто — обычный (§4, правило 6)"
          }
        ]
      },
      {
        "id": "reasons",
        "label": "Причины",
        "rules": "§2.2, §4, §12.1",
        "items": [
          {
            "path": "reasonCatalogs.hold.items",
            "label": "Причины удержания",
            "what": "Из чего выбирает оператор при «Отложить» и предельный срок каждой причины; системные — перерыв и нет связи"
          },
          {
            "path": "reasonCatalogs.mass_fault.items",
            "label": "Причины массового сбоя",
            "what": "Из чего выбирают при закрытии «Массовым сбоем»"
          },
          {
            "path": "session.breakReasons",
            "label": "Причины перерыва",
            "what": "Из чего выбирает оператор, уходя на перерыв"
          }
        ]
      },
      {
        "id": "escalation",
        "label": "Автоэскалация и алерты",
        "rules": "§8.3, §9",
        "items": [
          {
            "path": "escalation.enabled",
            "label": "Автоэскалация",
            "what": "Передавать ли не взятый вовремя инцидент по уровням; выключена — только нарушение и алерт"
          },
          {
            "path": "escalation.levels",
            "label": "Уровни",
            "what": "Адресат каждого уровня — пользователь или дежурная группа — и его норматив реакции"
          },
          {
            "path": "escalation.maxLevel",
            "label": "Потолок",
            "what": "Выше этого уровня инцидент не передаётся"
          },
          {
            "path": "escalation.onResolutionOverdue",
            "label": "Просрочка закрытия",
            "what": "Что делать, когда истёк норматив закрытия",
            "values": {
              "alert": "Нарушение и алерт",
              "escalate": "Нарушение, алерт и передача на следующий уровень"
            }
          },
          {
            "path": "escalation.reason",
            "label": "Запись журнала",
            "what": "Текст записи об автоэскалации"
          },
          {
            "path": "alerts.target",
            "label": "Получатель алертов",
            "what": "Пользователь или дежурная группа; получают те, кто на месте и с доступом к объекту"
          },
          {
            "path": "alerts.noRecipientLog",
            "label": "Если получателя нет",
            "what": "Запись журнала, когда алерт отправить некому"
          }
        ]
      },
      {
        "id": "limits",
        "label": "Лимиты",
        "rules": "§10.2, §11",
        "items": [
          {
            "path": "limits.maxActive",
            "label": "В работе одновременно",
            "what": "Сколько инцидентов оператор может вести сразу; группа сценария — один"
          },
          {
            "path": "limits.maxOnHold",
            "label": "Отложенных",
            "what": "Сколько оператор может отложить вручную"
          },
          {
            "path": "limits.maxBulk",
            "label": "В выборке",
            "what": "Сколько инцидентов можно отметить для группового действия"
          }
        ]
      },
      {
        "id": "session",
        "label": "Связь с оператором",
        "rules": "§12.3",
        "items": [
          {
            "path": "session.heartbeatSec",
            "label": "Признак активности",
            "what": "Как часто рабочее место сообщает, что оператор на связи"
          },
          {
            "path": "session.idleHoldSec",
            "label": "Нет связи — отложить",
            "what": "Через сколько молчания инцидент оператора уходит в «Отложен — нет связи»"
          },
          {
            "path": "session.idleReleaseSec",
            "label": "Нет связи — в очередь",
            "what": "Через сколько молчания отложенный по системной причине возвращается в очередь"
          }
        ]
      },
      {
        "id": "hotkeys",
        "label": "Горячие клавиши",
        "rules": "§13",
        "items": [
          {
            "path": "hotkeys",
            "label": "Набор по умолчанию",
            "what": "Клавиши для всех операторов; оператор может переназначить их себе"
          }
        ]
      },
      {
        "id": "access_groups",
        "label": "Группы доступа",
        "rules": "§5",
        "source": "GET /operator/admin/access-groups",
        "what": "Каким ролям какие группы устройств и устройства доступны: оператор видит только инциденты доступных объектов"
      },
      {
        "id": "duty_groups",
        "label": "Дежурные группы",
        "rules": "§8.1",
        "source": "GET /operator/admin/duty-groups",
        "what": "Кому можно адресовать инцидент вместо одного человека: название, роли, отдельные люди; порядок групп — приоритет"
      },
      {
        "id": "source_groups",
        "label": "Группы устройств",
        "rules": "§19",
        "source": "GET /operator/reference/source-groups",
        "what": "Дерево групп устройств: по нему строятся группы доступа и фильтры очереди"
      },
      {
        "id": "links",
        "label": "Справочные ссылки",
        "rules": "§7",
        "source": "GET /operator/reference/help-links",
        "what": "Меню справки: регламент, телефоны, схемы, контакты служб — общие ссылки и ссылки площадки"
      },
      {
        "id": "camera_links",
        "label": "Связи камер",
        "rules": "§19.1",
        "source": "GET /operator/admin/camera-links",
        "what": "Какие камеры показывать для устройства и в каком порядке: инцидент показывает камеры своего источника, первая — главная"
      }
    ],
    "notSettings": [
      {
        "path": "timers.reaction",
        "why": "кроме нормативов — устройство таймера: когда запускается и останавливается (модель, §4)"
      },
      {
        "path": "timers.resolution",
        "why": "кроме нормативов — устройство таймера (модель, §4)"
      },
      {
        "path": "timers.hold",
        "why": "срок удержания задаёт причина — вкладка «Причины»"
      },
      {
        "path": "reasonCatalogs.close_result",
        "why": "результаты закрытия — модель: от них зависят права, состояния и отчёты (§2.2)"
      },
      {
        "path": "reasonCatalogs.hold",
        "why": "кроме списка причин — поле и обязательность (модель)"
      },
      {
        "path": "reasonCatalogs.mass_fault",
        "why": "кроме списка причин — поле и обязательность (модель)"
      },
      {
        "path": "limits.groupCountsAsOneUnit",
        "why": "правило §11: группа сценария — одна единица лимита"
      },
      {
        "path": "session.states",
        "why": "состояния оператора — модель (§12.1)"
      }
    ]
  },
  "invariants": {
    "$comment": "§10.1. Проверяются сервером на каждом переходе. readOnlyByAgentState — в состояниях оператора с readOnly (перерыв, вышел) доступен только просмотр: переходы отклоняет условие agentReady (§10.1, правило 2).",
    "atomicServerSideTransition": true,
    "optimisticLocking": {
      "field": "version",
      "header": "If-Match"
    },
    "readOnlyByAgentState": true,
    "transferToSelfForbidden": true,
    "terminalOnlyViaReopen": true,
    "manualWinsOverTimer": true
  }
};
