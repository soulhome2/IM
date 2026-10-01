# Ревью IM 2026-10-01: полное, роль «продакт»

Дата: 2026-10-01. Проверяемый коммит: `f52d87e`, ветка `main`. Действующие правила: v4. Роли: продакт.

Что просмотрено глазами продакта:

- Vision — каждое требование;
- правила v4 — словарь, состояния и категории, права, нормативы, кнопки, горячие клавиши, открытые вопросы (§15), соответствие прототипу (§17);
- версии правил 001–004 — как они ведутся;
- README;
- прототип — сценарии и их варианты ответа, демо-данные, права, языки, панели, видео и карта.

Плюс автоматические проверки. Пункты с пометкой ✅ проверены запуском в Chrome. Остальное найдено чтением кода и документов.

Ссылки ведут на файлы в коммите `f52d87e`.

Номера и важность — по договорённостям в [reviews/README.md](../README.md). План исправлений — [plan.md](plan.md).

## Главное

1. В прототипе не работает «Принять» — основной сценарий передачи (BUG-01). Кнопка «Далее» подменяет выбранный вариант ответа первым из списка, поэтому классификация инцидента молча меняется (BUG-02).
2. Нигде не сказано, какая часть Vision покрыта правилами и прототипом, а какая отложена. Сервер, отчёты, конструктор сценариев и вход в систему не описаны, и непонятно, забыты они или отложены сознательно (DOC-02).
3. Два прямых требования Vision не описаны в правилах: роли с наборами прав (RULE-01) и режимы группировки событий (RULE-03).
4. Отчётность может врать:
   - итог сценария не связан с переходом, поэтому ложная тревога попадает то в закрытые, то в отменённые (RULE-02);
   - передачей можно обнулить норматив закрытия (RULE-07).
5. Правила заявляют, что прототип приведён к v4, хотя он отступает от них как минимум в семи местах (RULE-06).

Находки с метками других ролей пришли от автоматических проверок.

## Автоматические проверки

- Самопроверка: 10 из 14 шагов прошли. Упавшие шаги — BUG-01, BUG-02, BUG-03, BUG-04.
- Ссылки: 9 нерабочих, все в корневом README — DOC-01.
- Покрытие самопроверки в ревью одной ролью не оценивалось.

## 1. Системные причины

- **ARCH-01** [средний] *продакт, архитектор* **Каждая версия правил — полная копия примерно на 600 строк.** Для согласования с заказчиком и передачи разработчикам нужен один действующий документ, а сейчас их четыре. Кроме того, ошибки тянутся из версии в версию незамеченными:
  - ссылка «(§16)» у термина ITSM/ITIL ведёт не туда — с версии 2 ([002:24](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/002%20States%20rules%20IM.md?plain=1#L24));
  - «Перехватить» из «Ожидает принятия» противоречит описанию права — тоже с версии 2 ([002:230](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/002%20States%20rules%20IM.md?plain=1#L230)).

## 2. Ошибки в прототипе

- **BUG-01** [блокер] *тестировщик* ✅ **Кнопка «Принять» не работает.** Функция `accept.run(ev)` обращается к `payload`, который она не получает ([app.js:2224](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L2224)). Нажатие на кнопку или клавишу `A` даёт `Uncaught ReferenceError: payload is not defined`. Карточка не открывается, но инцидент уже молча переведён в «В работе». Это главный сценарий передачи: адресат не может нормально принять переданный ему инцидент. На любом показе прототипа это всплывёт первым.
  Как воспроизвести: фильтр «Мне на принятие» → «Принять» на INC‑1836.
- **BUG-02** [высокий] *тестировщик, продакт* ✅ **«Далее» подменяет ответ на шаге с вариантами.** `flushStepAnswer` записывает значение первого элемента с `data-ans`, а не отмеченного ([app.js:1937-1943](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L1937-L1943)). Выбрали «Ложная» — после «Далее» записано «Реальная». Для продукта это самое опасное: классификация уходит в результат закрытия и в отчётность. Ложные срабатывания будут посчитаны как реальные.
- **BUG-03** [низкий] *продакт, дизайнер* ✅ **Приоритет «низкий» есть в данных, но не в правилах.** В правилах приоритетов три: критический, высокий, средний ([004:43](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L43)). В прототипе у четырёх событий приоритет `low` ([app.js:1323](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L1323)), для него есть норматив закрытия ([app.js:1666](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L1666)), но нет цвета полоски ([styles.css:863-865](https://github.com/soulhome2/IM/blob/f52d87e/prototype/styles.css#L863-L865)). Нужно решить, есть ли такой приоритет в продукте.
- **BUG-04** [низкий] *UX* ✅ **Пять подписей не переведены на английский и испанский.** Это «Выбрать {id}», «Уровень эскалации», «Страница {p}», «План: {name}», «Шаги сценария» — всплывающие подсказки и подписи для экранного диктора ([app.js:3303](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L3303), [app.js:3317](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L3317), [app.js:3252](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L3252), [app.js:3771](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L3771), [app.js:3433](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L3433)). Ключей нет ни в одном словаре.

## 4. Противоречия и пробелы в правилах

- **RULE-01** [средний] *продакт, архитектор* **Нет ролей с наборами прав.** Vision требует назначать разные уровни прав: оператор, старший смены, администратор ([Vision:13](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L13)). Правила перечисляют права ([004:191-211](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L191-L211)) и говорят, что права выдаются роли ([004:22](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L22)). Но ни одной роли с её набором прав нет. В прототипе один набор прав на всех ([app.js:1690](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L1690)), и почти все права включены. Непонятно, что может рядовой оператор, а что только старший смены: например, перехват, переоткрытие, закрытие без обработки.
- **RULE-02** [средний] *продакт, архитектор* **Итог сценария не связан с переходом.** Правила отделяют отмену от закрытия: ложная тревога и плановая проверка — это не «успешно обработано» ([004:94](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L94), причины отмены — [004:114-116](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L114-L116)). Но в сценариях есть те же исходы как варианты ответа, и после них инцидент обычно закрывается:
  - «Ложная», «Персонал / ложная», «Ошибка детектора», «Ложная сработка детектора» ([app.js:47](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L47), [app.js:73](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L73), [app.js:123](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L123), [app.js:181](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L181));
  - «Тест системы» ([app.js:53](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L53));
  - «Требует выезда» ([app.js:47](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L47)) — после него инцидент можно сразу закрыть, хотя наряд ещё едет. Для этого в правилах есть удержание «Выезд наряда» ([004:105](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L105)).

  Демо-данные показывают оба пути сразу. INC‑1831 закрыт с итогом «Ложная, тест системы» ([app.js:1461](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L1461)), а другой инцидент отменён с причиной «Ложная тревога». Одно и то же событие попадёт в отчётах то в закрытые, то в отменённые.
- **RULE-03** [средний] *продакт* **Режимы группировки из Vision не описаны.** Vision требует группировать события по региону, по типу события, по типу объекта, а также по своему списку объектов, который обрабатывается как один ([Vision:20](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L20)). В правилах группировки нет. Групповая обработка в §11 — это другое: несколько однотипных событий одной карточкой. В прототипе есть только дерево объектов и сквозные подборки по видам устройств ([app.js:373](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L373)). Группировки по типу события и своих списков объектов нет, и нигде не сказано, что они отложены.
- **RULE-04** [низкий] *продакт, UX* **Горячие клавиши: «под себя» или в схеме.** Vision требует настраивать горячие клавиши под себя ([Vision:26](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L26)). Правила проверяют дубли клавиш «при сохранении схемы» ([004:479](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L479)), то есть считают клавиши настройкой администратора. В личных настройках оператора их нет ([004:216](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L216)). Прототип обещает «задавать под себя» ([index.html:328](https://github.com/soulhome2/IM/blob/f52d87e/prototype/index.html#L328)). Кто и что настраивает, не решено.
- **RULE-05** [средний] *продакт* **У открытых вопросов нет владельца и срока.** В §15 пять вопросов с вариантами, но без того, кто решает и до какого момента ([004:554-564](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L554-L564)). От них зависят отчётность (разделять ли «выполнено» и «закрыто»), нормативы (календарь или смена) и переоткрытие (срок). Без владельца они дойдут до разработчиков нерешёнными.
- **RULE-06** [средний] *продакт, разработчик* **Правила заявляют полное соответствие прототипа.** «Прототип приведён к v4» ([004:579](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L579), [004:7](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L7)). При этом прототип отступает от правил:
  - `Esc` в своей карточке не откладывает инцидент, а только возвращает к очереди ([004:476](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L476), [app.js:3940](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L3940));
  - в очереди у своих «В работе» и «Отложен» есть «Закрыть», а в §7 нет ([app.js:2659](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L2659));
  - в карточке кнопка подписана «Закрыть», а не «Закрыть без обработки» ([app.js:2379](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L2379));
  - при автоэскалации открытая карточка закрывается, а не переходит в просмотр ([004:358](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L358), [app.js:2969](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L2969));
  - нет возврата в очередь после долгого обрыва сессии ([004:251](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L251));
  - нет ручного исключения инцидента из группы ([004:424](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L424));
  - эмуляция коллег меняет данные в обход правил ([app.js:4459](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L4459)).

  Кто согласует правила по прототипу, увидит не то, что написано.
- **RULE-07** [высокий] *продакт, архитектор* **Передачей можно обнулить норматив закрытия.** «Передать» останавливает норматив закрытия, а «Принять» запускает его заново ([004:232](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L232)). Норматив реакции правила от этого защищают (§8.3), а норматив закрытия — нет. Таблица §4 вообще говорит, что этот норматив останавливается только при закрытии или отмене ([004:181](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L181)). Для продукта это значит, что просрочку закрытия можно скрыть передачей коллеге, и отчёты о времени обработки будут неверны.
- **RULE-08** [низкий] *продакт, архитектор* **«Отложен» считается ожидающим наравне с новыми.** Состояние «Отложен» отнесено к категории `pending` вместе с ничьими новыми инцидентами ([004:86](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L86)). А от категории зависят счётчики, группировка очереди и отчёты ([004:121](https://github.com/soulhome2/IM/blob/f52d87e/Specification/State_rules/004%20States%20rules%20IM.md?plain=1#L121)). В «ждут реакции» попадут инциденты, с которыми уже работают.

## 5. Документы

- **DOC-01** [средний] *разработчик* ✅ **В корневом README 9 нерабочих ссылок.** Не открывается ни один документ из таблицы «Документы»: правила и Vision перенесли в `Specification/`, а ссылки остались прежними ([README.md:27-32](https://github.com/soulhome2/IM/blob/f52d87e/README.md?plain=1#L27-L32)). README — точка входа для коллег, заказчика и разработчиков. Полный список выдаёт `python3 tools/check_links.py`.
- **DOC-02** [средний] *продакт* **Нет сверки Vision с правилами и прототипом.** README говорит, что репозиторий — про рабочее место оператора ([README.md:3](https://github.com/soulhome2/IM/blob/f52d87e/README.md?plain=1#L3)). Но нигде не сказано, какие требования Vision покрыты, какие частично, а какие отложены или вне этого репозитория. Сверка по каждому требованию:

  | Требование Vision | Где | Состояние |
  |---|---|---|
  | API с плагинами к внешнему ПО ([5](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L5)) | — | нет |
  | Работа в любом браузере ([6](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L6)) | прототип, телефон — §7 | есть |
  | HTTPS и вход в систему ([7](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L7)) | — | нет |
  | Обработка по сценариям ([11](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L11)) | прототип, §14.5 | есть |
  | Видеоархив и карта ([12](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L12)) | прототип | есть |
  | Уровни прав: оператор, старший, администратор ([13](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L13)) | права §5, ролей нет | частично, RULE-01 |
  | Обмен событиями, перехват, контроль оператора ([14-16](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L14-L16)) | §6.1, §6.3, прототип | есть |
  | Группировка по региону, типу события, типу объекта, свой список ([20](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L20)) | дерево объектов в прототипе | частично, RULE-03 |
  | Групповая обработка ([21](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L21)) | §11, прототип | есть |
  | Состав, расположение и размер панелей ([25](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L25)) | скрыть, показать, размер; переставить нельзя | частично |
  | Горячие клавиши под себя ([26](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L26)) | — | нет, RULE-04 |
  | Время отдыха ([27](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L27)) | перерыв вручную, §12; расписания нет | частично |
  | Меню вспомогательных ссылок с настройкой ([28](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L28)) | меню справки в прототипе; настройка не описана | частично |
  | Панели: группы, события, обработка, карта, видео ([32-36](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L32-L36)) | прототип | есть |
  | Дашборды ([37](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L37)) | — | открытый вопрос, DOC-03 |
  | Диспетчер событий: фильтры, хранение, источники ([43-46](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L43-L46)) | — | нет |
  | Таймеры и автоэскалация ([47](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L47)) | §4, §9 | есть |
  | Конструктор сценариев, экспорт и импорт ([51](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L51), [53](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L53)) | вопрос в §15 | нет |
  | Типы элементов сценария ([52](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L52)) | прототип: флажок, выбор, список, поле, макрос | есть |
  | Архив и онлайн ([59](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L59)) | прототип | есть |
  | Несколько камер одновременно, камеры региона ([60](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L60)) | одна камера с переключением ([app.js:3649](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L3649)) | частично |
  | Место инцидента на карте ([64](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L64)) | прототип, автоматически | есть, вопрос — DOC-03 |
  | Результаты в AxxonData ([70](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L70)) | §14.2 | частично |
  | Отчёты, кадры и карта в отчёте, сегментация, экспорт, сводные ([71-77](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L71-L77), [83](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L83)) | — | нет |
  | Журнал действий оператора ([81](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L81)) | журнал по каждому инциденту; общего журнала оператора нет | частично |

  Без такой таблицы заказчик и разработчики не отличат то, что отложено сознательно, от того, что забыли.
- **DOC-03** [низкий] *продакт* **Открытые вопросы Vision нигде не ведутся.** Vision оставляет три вопроса, и ни одного из них нет среди открытых вопросов правил (§15):
  - нужны ли дашборды ([Vision:37](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L37));
  - где настраивать связи камер ([Vision:60](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L60));
  - показывать место на карте автоматически или по запросу ([Vision:64](https://github.com/soulhome2/IM/blob/f52d87e/Specification/AxxonNext%20Incident%20Manager%20Vision.md?plain=1#L64)).

  Последний прототип по сути решил — «автоматически», — но решение нигде не записано.
- **DOC-04** [низкий] *продакт* **Три языка интерфейса без требования.** Прототип переключается между русским, английским и испанским ([app.js:9-13](https://github.com/soulhome2/IM/blob/f52d87e/prototype/app.js#L9-L13)). Ни в Vision, ни в правилах языков нет. Перевод стоит денег на каждое изменение: BUG-04 показывает, что он уже отстаёт. Нужно решить, какие языки нужны продукту и кто ведёт переводы.
- **DOC-05** [низкий] *продакт* **Название продукта везде разное.** «AxxonNext Incident Manager» — в имени файла Vision, «Axxon Incident Manager» — в README и заголовке прототипа ([README.md:3](https://github.com/soulhome2/IM/blob/f52d87e/README.md?plain=1#L3), [index.html:6](https://github.com/soulhome2/IM/blob/f52d87e/prototype/index.html#L6)). В шапке прототипа — «Incident Manager» и «AxxonsSoft / ITV» с опечаткой ([index.html:18-19](https://github.com/soulhome2/IM/blob/f52d87e/prototype/index.html#L18-L19)).

## Ограничения проверки

- Смотрела только роль «продакт». Архитектура, поведение прототипа, удобство, дизайн и взгляд разработчика глубоко не проверялись. Находки с их метками пришли только от автоматических проверок.
- Бизнес‑приоритеты неизвестны. Что из Vision нужно в этой фазе, решают люди, поэтому находки продакта в плане сформулированы как вопросы.
- Серверная часть, отчёты и машина состояний (отдельный репозиторий) не проверялись: их здесь нет.
- Самопроверка и ссылки прогнаны только в Chrome на Linux.
