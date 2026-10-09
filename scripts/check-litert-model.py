"""Run the app's exported prompt/schema against a real LiteRT-LM model on desktop.

Install the optional test runtime: pip install litert-lm-api==0.18.0
Prepare request: cd app && dart run tool/check_local_ai.dart prepare SOURCE.txt REQUEST.json
Run: python scripts/check-litert-model.py MODEL.litertlm REQUEST.json OUTPUT.json
Validate: cd app && dart run tool/check_local_ai.dart check REQUEST.json OUTPUT.json
This verifies model behavior; it does not replace testing the Android APK on a phone.
"""
import argparse
import json
import time
from pathlib import Path


def main():
    import litert_lm

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("request", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--unconstrained", action="store_true")
    args = parser.parse_args()
    request = json.loads(args.request.read_text(encoding="utf-8"))
    started = time.monotonic()
    engine = litert_lm.Engine(str(args.model), backend=litert_lm.Backend.CPU(thread_count=4),
                              max_num_tokens=4096)
    responses = []
    try:
        for index, fragment in enumerate(request["fragments"]):
            conversation = engine.create_conversation(
                system_message=request["instruction"],
                chat_template=request["chatTemplate"],
                sampler_config=litert_lm.SamplerConfig(top_k=40, top_p=1.0, temperature=0.0),
                max_output_tokens=1536,
                constrained_decoding_config=None if args.unconstrained else litert_lm.ConstrainedDecodingConfig(
                    enable=True, provider=litert_lm.LiteRtLmConstraintProviderType.LL_GUIDANCE),
            )
            try:
                response = conversation.send_message(
                    "Источник рецепта:\n" + fragment,
                    response_format=None if args.unconstrained else litert_lm.ResponseFormat.json(request["schema"]),
                )
                responses.append(str(response))
                print(f"Processed fragment {index + 1}/{len(request['fragments'])}", flush=True)
            finally:
                conversation.close()
    finally:
        engine.close()
    args.output.write_text(json.dumps(responses, ensure_ascii=False), encoding="utf-8")
    print(f"Saved model output; elapsed {time.monotonic() - started:.1f}s on desktop CPU.")


if __name__ == "__main__":
    main()
