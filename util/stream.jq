try (
  fromjson |
  if .type == "assistant" then
    .message.content[] |
    if .type == "text" then .text
    elif .type == "tool_use" then
      (.input | to_entries | first) as $e |
      "> \(.name)\(if $e then ": \($e.value | tostring | .[0:60])" else "" end)"
    else empty
    end
  elif .type == "user" then
    .message.content[]? |
    if .type == "tool_result" then
      if .is_error then "  ERR  tool_result (error)"
      else "  ok   tool_result"
      end
    else empty
    end
  elif .type == "system" then
    if .subtype == "task_started" then "> Task: \(.description)"
    elif .subtype == "task_progress" then "  \(.description)"
    elif .subtype == "init" then "[init session=\(.session_id // "?") model=\(.model // "?")]"
    else "[system: \(.subtype // "?")]"
    end
  elif .type == "result" then
    if .subtype == "success" then .result
    else "[result: \(.subtype)]"
    end
  else "[event: \(.type)]"
  end
) catch empty
