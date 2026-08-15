#!/usr/bin/env python3
"""A/B two system prompts on the same texts against the real xAI API.

Usage:
    python3 tests/compare_prompts.py ru2en/prompt.txt ru2en/prompt.candidate.txt
"""

import concurrent.futures
import json
import subprocess
import sys
import urllib.request

MODEL = "grok-4.20-0309-non-reasoning"
ENDPOINT = "https://api.x.ai/v1/chat/completions"

CASES = [
    "Братан я и так сделал большую скидку\nДумаю 20$ не сыграют роли но качестве будет на высшем уровне",
    "привет, за пост в закрепе беру 40$, за обычный 25$\nесли берешь пакет из трех - сделаю 90$",
    "честно говоря не думаю что это зайдет моей аудитории\nдавай лучше сделаю квоут с моим комментарием, так будет органичнее",
    "лол это лучшее что я видел за неделю",
    "не, за такие деньги не работаю\nмой минимум 50$ и это уже со скидкой для тебя",
    "скинь тз в лс, гляну вечером и отпишусь\nесли все ок - запущу завтра утром",
    "слушай я честно хз зайдет ли это\nаудитория у меня в основном про спорт, а у тебя продукт для дизайнеров",
    "го созвон на 15 минут, обсудим детали\nсегодня после 6 вечера свободен",
    # slang address forms the model likes to silently drop
    "йо броски давай делать квот за 200$$$",
    "здарова кент, го работать",
    "бро скинь чек как оплатишь",
    # singular must stay singular, plural must stay plural
    "давай сделаю квот",
    "могу сделать пару квотов и один пост",
    "чувак ты серьезно за такие деньги хочешь три поста и два квота",
]


def api_key() -> str:
    out = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-s", "ru2en-xai", "-w"],
        capture_output=True,
        text=True,
        check=True,
    )
    return out.stdout.strip()


def translate(key: str, system: str, text: str) -> str:
    body = json.dumps(
        {
            "model": MODEL,
            "temperature": 0.3,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": text},
            ],
        }
    ).encode()
    req = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)
    return payload["choices"][0]["message"]["content"]


def block(label: str, text: str) -> str:
    lines = text.split("\n")
    head = f"  {label}: {lines[0]}"
    rest = [f"  {' ' * len(label)}  {line}" for line in lines[1:]]
    return "\n".join([head, *rest])


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    labels = []
    prompts = []
    for path in sys.argv[1:3]:
        with open(path, encoding="utf-8") as f:
            prompts.append(f.read().strip())
        labels.append(path.split("/")[-1].replace("prompt", "").strip(".txt") or "current")

    key = api_key()
    a_label, b_label = labels[0][:9].ljust(9), labels[1][:9].ljust(9)

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        jobs = [
            (case, pool.submit(translate, key, prompts[0], case), pool.submit(translate, key, prompts[1], case))
            for case in CASES
        ]
        for n, (case, fa, fb) in enumerate(jobs, 1):
            print(f"\n=== {n} " + "=" * 60)
            print(block("RU", case))
            print(block(a_label, fa.result()))
            print(block(b_label, fb.result()))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
