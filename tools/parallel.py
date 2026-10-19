"""Параллельный прогон мутаций: ключи --jobs и --shard для check_code_mutations.py и check_mutations.py.

--jobs=N   — сколько мутаций идёт одновременно; по умолчанию три четверти ядер (у каждой мутации свой Chrome,
             он сам занимает больше одного ядра). --jobs=1 — по одной, как раньше.
--shard=K/M — только K-я из M частей списка мутаций (каждая M-я, начиная с K-й): так CI раскладывает мутации
             на M задач, которые идут одновременно. Без ключа — все.
Набор тестов и вердикт мутации от этого не меняются: меняется только, сколько мутаций идёт сразу.
"""
import os
import sys


def options(argv=None):
    """(имена мутаций, jobs, shard K, shard M) из командной строки."""
    argv = sys.argv[1:] if argv is None else argv
    jobs = max(1, (os.cpu_count() or 2) * 3 // 4)
    shard = (1, 1)
    names = []
    for a in argv:
        if a.startswith("--jobs="):
            jobs = max(1, int(a.split("=", 1)[1]))
        elif a.startswith("--shard="):
            k, m = a.split("=", 1)[1].split("/")
            shard = (int(k), int(m))
            if not 1 <= shard[0] <= shard[1]:
                sys.exit(f"--shard={a.split('=', 1)[1]}: нужно K/M, 1 ≤ K ≤ M")
        elif not a.startswith("-"):
            names.append(a)
    return names, jobs, shard[0], shard[1]


def part(items, k, m):
    """K-я из M частей: элементы с номерами k-1, k-1+m, … — части примерно равны и не пересекаются."""
    return [x for i, x in enumerate(items) if i % m == k - 1]
