create() {
  calc_options
  calc_resolve_loop
  calc_actions_str
  calc_functions_str
  calc_variables_str

  readonly R_TOOL_FILE="${tool_name}/${tool_name}.sh"
cat > "$R_TOOL_FILE" << EOF
#!/bin/bash

$ret_variables_str

$ret_description_var_str

## 一般日志打印
info_log() {
  echo -e "\${R_COLOR_G}[info]\$*\${R_RESET}"
}
## 错误日志打印
error_log() {
  echo -e "\${R_COLOR_R}[error]\$*\${R_RESET}" >&2
  exit 1
}
## 警告日志打印
warn_log() {
  echo -e "\${R_COLOR_Y}[warn]\$*\${R_RESET}"
}

## 获取变量
# \$1: Var Name, 变量名称
get_var() {
  local var_name="\$1"
  [ -z "\$var_name" ] && return
  eval echo \"'\$'"\${var_name}"\"
}

## 拼接字符串，例如：TEST-1234,PM-1025
# \$1 左边字符串
# \$2 右边字符串
# \$3 拼接符号，默认逗号
append() {
  local left_string="\$1"
  local right_string="\$2"
  local append_symbol="\$3"
  [[ -z \$append_symbol ]] && append_symbol=","
  if [[ -n \$left_string ]]; then
    left_string="\$left_string\$append_symbol\$right_string"
  else
    left_string="\$right_string"
  fi
  echo -n "\$left_string"
}

## 检查环境
# \$1: 要检查的命令, 以空格隔开, 例如:check_command "jq" "tar"
check_command() {
  local to_checks=("\$@")
  local cmd
  local not_found_cmd=""
  for cmd in "\${to_checks[@]}"; do
    command -v "\${cmd}" > /dev/null 2>&1 || not_found_cmd=\$(append "\${not_found_cmd}" "\${cmd}" "、")
  done
  [[ -n "\${not_found_cmd}" ]] && error_log "\${not_found_cmd}命令不存在, 请自行安装."
}

## 解释Action
# \$1: Action
# \$2: Description
# \$3: Use Example
explain_action() {
  local -r indent="25"
  local action="\$1"
  local description="\$2"
  local use_example="\$3"
  if [ -n "\$use_example" ]; then
    printf "  %-\${indent}s %s\n   %\${indent}s示例: %s\n\n"  "\$action" "\$description" "" "\$use_example"
  else
    printf "  %-\${indent}s %s\n\n"  "\$action" "\$description"
  fi
}

## 解释某个Action(带参数的描述)
# \$1: Action
# \$2: Param
# \$3: Description
# \$4: Value Example
explain_action_with_param() {
  local -r indent="25"
  local action="\$1"
  local params=("\${@:2}")
  local var_name
  printf "%s %s\n\n" "$tool_name" "\$action"
  printf "%s\n" "requires:"
  for param in "\${params[@]}"; do
    var_name="R_PARAM_\$(echo "\${param^^}" | tr '-' '_')_DESCRIPTION"
    printf "  %-\${indent}s %s\n" "--\$param" "\$(get_var "\$var_name")"
  done
  if [ -z "\$options_str" ]; then
    return
  fi
  echo
  IFS="," read -r -a option_params_arr <<< "\$options_str"
  printf "%s\n" "options:"
  for option_param in "\${option_params_arr[@]}"; do
    var_name="R_PARAM_\$(echo "\${option_param^^}" | tr '-' '_')_DESCRIPTION"
    printf "  %-\${indent}s %s\n" "--\$option_param" "\$(get_var "\$var_name")"
  done
}

## 检查Action所需要的param
# \$1: Action
# \$2...\$n: Required Param
check_action_param() {
  local action="\$1"
  local to_checks=("\${@:2}")
  if [ " -h -- '\${action}'" == "\$parameters" ] || [ " --help -- '\${action}'" == "\$parameters" ]; then
    explain_action_with_param "\$action" "\${to_checks[@]}"
    exit 0
  fi
  local param
  local required_param=""
  for param in "\${to_checks[@]}"; do
    echo "\$parameters" | grep "'\$action'" | grep -v "\-\-\$param" > /dev/null && required_param=\$(append "\${required_param}" "--\${param}")
  done
  [[ -n "\${required_param}" ]] && error_log "Action '\$action' requires \${required_param} param."
}

$ret_actions_params_check_str

$ret_functions_str

$ret_actions_str

$ret_help_action_str

## shell执行的核心部分
readonly R_LONG_OPTIONS="$ret_long_options,help"
readonly R_SHORT_OPTIONS="$ret_short_options,h"
readonly R_TOOL_ACTIONS="$tool_actions"
if ! parameters=\$(getopt -o "\$R_SHORT_OPTIONS" -l "\$R_LONG_OPTIONS" -n "\$0" -- "\$@"); then
  exit 1
fi
eval set -- "\$parameters"

while true; do
  case "\$1" in
${ret_loop_code}
  "--help" | "-h")
    shift 1
    ;;
  --)
    shift
    action=\$1
    echo "\$R_TOOL_ACTIONS" | grep -q "\$action" || error_log "Unsupported action: \$action, available actions: \$R_TOOL_ACTIONS"
    shift
    break
    ;;
  *)
    echo "Unknown Error: \$1"
    exit 1
    ;;
  esac
done


if [ -z "\$action" ]; then
  action="help"
else
  eval "${R_ACTION_PARAMS_CHECK_PREFIX}\${action//-/_}"
fi
## 脚本开始执行，执行具体的action
eval "${R_ACTION_PREFIX}\${action//-/_}"

EOF
  chmod +x "$R_TOOL_FILE"

}