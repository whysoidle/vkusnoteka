import 'dart:convert';

// The same non-thinking ChatML framing as Android/macOS, with a schema supplied
// for each fragment (including recipe-index constraints for multi-recipe video).
Map<String, dynamic> windowsCompletionBody(
  String instruction,
  String fragment,
  String schema,
) => {
  'prompt':
      '<|im_start|>system\n$instruction<|im_end|>\n'
      '<|im_start|>user\n${fragment.replaceAll('<|', '‹|').replaceAll('|>', '|›')}<|im_end|>\n'
      '<|im_start|>assistant\n<think>\n\n</think>\n\n',
  'json_schema': jsonDecode(schema),
  'temperature': 0,
  'top_k': 40,
  'top_p': 1.0,
  'min_p': 0,
  'seed': 42,
  'n_predict': 2048,
  'cache_prompt': false,
  'stream': false,
};
