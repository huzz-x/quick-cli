#!/usr/bin/env bash

###--------------------------------------------------------------------------------------------
## 开始定义只读变量
readonly R_COLOR_G="\x1b[0;32m"
readonly R_COLOR_R="\x1b[1;31m"
readonly R_COLOR_Y="\x1b[1;33m"
readonly R_RESET="\x1b[0m"
readonly R_LARK_BASEURL="https://open.feishu.cn"
readonly R_LARK_API_BASEURL="$R_LARK_BASEURL/open-apis"
readonly R_TOOL_NAME="lark-cli"
readonly R_TOOL_VERSION="1.0.0"

# Action
readonly R_ACTION_DEFAULT="help"
readonly R_ACTION_SEND_MSG="send-msg"
readonly R_ACTIONS="$R_ACTION_DEFAULT,$R_ACTION_SEND_MSG"
readonly R_ACTIONS_IN_CASE="${R_ACTIONS//,/|}"

# Param And Description
readonly R_PARAM_APP_ID="app-id"
# shellcheck disable=SC2034
readonly R_PARAM_APP_ID_DESCRIPTION="应用的appID"
readonly R_PARAM_APP_SECRET="app-secret"
# shellcheck disable=SC2034
readonly R_PARAM_APP_SECRET_DESCRIPTION="应用的appSecret"
readonly R_PARAM_EMAILS="emails"
# shellcheck disable=SC2034
readonly R_PARAM_EMAILS_DESCRIPTION="以邮箱来指定飞书消息的接收人, 可以是多个, 以英文的逗号隔开, 例如: \"xxx@xx.cn,yy@yy.cn\""
readonly R_PARAM_MSG="msg"
# shellcheck disable=SC2034
readonly R_PARAM_MSG_DESCRIPTION="待发送的消息或消息模板(文件), 消息字符串具体格式请参考: https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/im-v1/message"
# Default Param Value


###--------------------------------------------------------------------------------------------
## 开始定义方法
## 一般日志打印
info_log() {
  echo -e "${R_COLOR_G}[info]$*${R_RESET}"
}
## 错误日志打印
error_log() {
  echo -e "${R_COLOR_R}[error]$*${R_RESET}" >&2
  exit 1
}
## 警告日志打印
warn_log() {
  echo -e "${R_COLOR_Y}[warn]$*${R_RESET}"
}

## 获取变量
# $1: Var Name, 变量名称
get_var() {
  local var_name="$1"
  [ -z "$var_name" ] && return
  eval echo \"'$'"${var_name}"\"
}

## 拼接字符串，例如：TEST-1234,PM-1025
# $1 左边字符串
# $2 右边字符串
# $3 拼接符号，默认逗号
append() {
  local left_string="$1"
  local right_string="$2"
  local append_symbol="$3"
  [[ -z $append_symbol ]] && append_symbol=","
  if [[ -n $left_string ]]; then
    left_string="$left_string$append_symbol$right_string"
  else
    left_string="$right_string"
  fi
  echo -n "$left_string"
}

## 检查环境
# $1: 要检查的命令, 以空格隔开, 例如:check_command "jq" "tar"
check_command() {
  local to_checks=("$@")
  local cmd
  local not_found_cmd=""
  for cmd in "${to_checks[@]}"; do
    command -v "${cmd}" > /dev/null 2>&1 || not_found_cmd=$(append "${not_found_cmd}" "${cmd}" "、")
  done
  [[ -n "${not_found_cmd}" ]] && error_log "${not_found_cmd}命令不存在, 请自行安装."
}

## 使用eval创建动态的变量, 仅适用于简单变量
# $1: 变量名称
# $2: 变量值
create_dynamic_var() {
  local name="$1"
  local value="$2"
  # 需要将"-"转换成"_"
  name="${name//-/_}"
  eval "$name=$value"
}
## 获取简单变量
# $1: 变量名称
get_dynamic_var() {
  local name="$1"
  # 需要将"-"转换成"_"
  name="${name//-/_}"
  get_var "$name"
}

## 创建用户ID的动态变量
# $1: Email
# $2: Value
create_user_id_dynamic_var() {
  local -r email="$1"
  local -r value="$2"
  local -r name="${email//[@\.]/_}_user_id"
  create_dynamic_var "$name" "$value"
}
## 获取用户ID的动态变量
# $1: Email
get_user_id_dynamic_var() {
  local -r email="$1"
  local -r name="${email//[@\.]/_}_user_id"
  get_dynamic_var "$name"
}

## 解释Action
# $1: Action
# $2: Description
# $3: Use Example
explain_action() {
  local -r indent="25"
  local action="$1"
  local description="$2"
  local use_example="$3"
  if [ -n "$use_example" ]; then
    printf "  %-${indent}s %s\n   %${indent}s示例: %s\n\n"  "$action" "$description" "" "$use_example"
  else
    printf "  %-${indent}s %s\n\n"  "$action" "$description"
  fi
}

## 解释某个Action(带参数的描述)
# $1: Action
# $2: Param
# $3: Description
# $4: Value Example
explain_action_with_param() {
  local -r indent="25"
  local action="$1"
  local params=("${@:2}")
  local var_name
  printf "%s %s\n\n" "$R_TOOL_NAME" "$action"
  printf "%s\n" "requires:"
  for param in "${params[@]}"; do
    var_name="R_PARAM_$(echo "${param^^}" | tr '-' '_')_DESCRIPTION"
    printf "  %-${indent}s %s\n" "--$param" "$(get_var "$var_name")"
  done
  if [ -z "$options_params" ]; then
    return
  fi
  echo
  IFS="," read -r -a option_params_arr <<< "$options_params"
  printf "%s\n" "options:"
  for option_param in "${option_params_arr[@]}"; do
    var_name="R_PARAM_$(echo "${option_param^^}" | tr '-' '_')_DESCRIPTION"
    printf "  %-${indent}s %s\n" "--$option_param" "$(get_var "$var_name")"
  done
}

## 检查Action所需要的param
# $1: Action
# $2...$n: Required Param
check_action_param() {
  local action="$1"
  local to_checks=("${@:2}")
  echo "$action"
  if [ " -- '${action}'" == "$parameters" ]; then
    explain_action_with_param "$action" "${to_checks[@]}"
    exit 0
  fi
  local param
  local required_param=""
  local -r one_line_parameters=$(echo "${parameters}" | sed ':a;N;s/\n//g;ta')
  local param_val
  for param in "${to_checks[@]}"; do
    param_val=$(get_var "${param//-/_}")
    [ -z "${param_val// /}" ] && error_log "${param}不允许为空"
    [ -z "$param" ] && error_log "$param"
    echo "$one_line_parameters" | grep "'$action'" | grep -v "\-\-$param" > /dev/null \
      && required_param=$(append "${required_param}" "--${param}")
  done
  [[ -n "${required_param}" ]] && error_log "'$action' requires ${required_param} param."
}

## 输出脚本使用方法
action_help() {
  printf "%s\n  %s\n\n" "名称:"  $R_TOOL_NAME
  printf "%s\n  %s\n\n" "版本:"  $R_TOOL_VERSION
  printf "%s\n  %s\n\n" "Actions:"  $R_ACTIONS
  explain_action "$R_ACTION_DEFAULT" "输出帮助文档"
  explain_action "$R_ACTION_SEND_MSG" "发送飞书消息" "$R_TOOL_NAME $R_ACTION_SEND_MSG --app-id=<app_id> --app-secret=<app_secret> --emails=\"demo@example.cn\" --msg=\"{\\\"msg_type\\\":\\\"text\\\",\\\"content\\\":{\\\"text\\\":\\\"hh\\\"}}\""
}

## 获取Access Token, token的值被设置在<access_token>变量中
# $1: APP ID
# $2: APP Secret
get_access_token() {
  local -r app_id="$1"
  [[ -z "$app_id" ]] && error_log "app_id不允许为空."
  local -r app_secret="$2"
  [[ -z "$app_secret" ]] && error_log "app_secret不允许为空."
  local -r res=$(curl --location --request POST -s -w "\n%{http_code}" \
    "${R_LARK_API_BASEURL}/auth/v3/tenant_access_token/internal/" \
    --header "Content-Type: application/json" \
    --data-raw "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}")
  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  local -r error_msg="获取Access Token失败. app_id: ${app_id}. response code: ${res_ret_code}, body: ${res_ret_body}"
  [[ $res_ret_code != 200 ]] && error_log "$error_msg"
  local -r code=$(echo "$res_ret_body" | jq -r .code)
  [[ $code != 0 ]] && error_log "$error_msg"
  access_token=$(echo "$res_ret_body" | jq -r .tenant_access_token)
}

## 根据邮箱获取飞书用户的user_id, user_id的值被设置在一个动态变量中, 例如:
## 邮箱demo@example.cn对应的user_id被设置在ji_chen_example_cn_user_id变量中, 可以使用get_user_id_dynamic_var方法直接获取值
# $1: Access Token
# $2: Emails, 以逗号分割, 例如: xxx@xx.cn,yy@yy.cn
get_user_id() {
  local -r access_token="$1"
  [[ -z "$access_token" ]] && error_log "access_token不允许为空."
  local -r emails="$2"
  [[ -z "$emails" ]] && error_log "email不允许为空."

  local request_param=""
  IFS="," read -r -a email_arr <<< "$emails"
  for email in "${email_arr[@]}"; do
    request_param=$(append "$request_param" "emails=${email}" "&")
  done

  local -r res=$(curl --location --request GET -s -w "\n%{http_code}" \
    "${R_LARK_API_BASEURL}/user/v1/batch_get_id?${request_param}" \
    --header "Authorization: Bearer ${access_token}")
  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  local -r error_msg="获取用户ID失败. emails: ${emails}. response code: ${res_ret_code}, body: ${res_ret_body}"
  [[ $res_ret_code != 200 ]] && error_log "$error_msg"
  local -r code=$(echo "$res_ret_body" | jq -r .code)
  [[ $code != 0 ]] && error_log "$error_msg"
  local -r email_users=$(echo "$res_ret_body" | jq -r .data.email_users)
  local user_id_exists
  for email in "${email_arr[@]}"; do
    user_id_exists=$(echo "$email_users" | jq -r ".\"${email}\"[0].user_id")
    [ "$user_id_exists" == "null" ] && continue
    create_user_id_dynamic_var "$email" "$user_id_exists"
  done
}

## 发送飞书消息
# $1: Access Token
# $2: User ID
# $3: Msg Body
send_msg() {
  local -r access_token="$1"
  [[ -z "$access_token" ]] && error_log "access_token不允许为空."
  local -r user_id="$2"
  [[ -z "$user_id" ]] && error_log "user_id不允许为空."
  local -r msg_body="$3"
  [[ -z "$msg_body" ]] && error_log "msg_body不允许为空."

  local -r res=$(curl --location --request POST -s -w "\n%{http_code}" \
    "${R_LARK_API_BASEURL}/message/v4/send/?user_id=${user_id}" \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer ${access_token}" \
    --data-raw "$msg_body")
  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  local -r error_msg="发送消息失败. email: ${email}. response code: ${res_ret_code}, body: ${res_ret_body}"
  [[ $res_ret_code != 200 ]] && error_log "$error_msg"
  local -r code=$(echo "$res_ret_body" | jq -r .code)
  [[ $code != 0 ]] && error_log "$error_msg"
  echo "$res_ret_body"
}

## 发送飞书消息
action_send_msg() {
  # Action所需参数检查, options_params通过全局变量指定
  options_params=""
  check_action_param $R_ACTION_SEND_MSG $R_PARAM_APP_ID $R_PARAM_APP_SECRET $R_PARAM_EMAILS $R_PARAM_MSG
  # 默认传递的是文本格式的消息
  local msg_str="$msg"
  if [ -f "$msg" ]; then
    # 如果传递的是文件, 一般情况下, 可以使用envsubst命令替换变量, 但有的系统可能没有这个命令, 这里使用eval实现
    local -r msg_str_origin=$(cat "$msg")
    # 将"换成\""
    msg_str=$(eval "echo \"${msg_str_origin//\"/\\\"\"}\"")
  fi

  # 检查一下json格式
  echo "$msg_str" | jq . > /dev/null 2>&1 || error_log "错误的消息格式: --${R_PARAM_MSG}=\"$msg_str\""
  get_access_token "$app_id" "$app_secret"
  get_user_id "$access_token" "$emails"
  local user_id
  IFS="," read -r -a email_arr <<< "$emails"
  for email in "${email_arr[@]}"; do
    user_id=$(get_user_id_dynamic_var "$email")
    send_msg "$access_token" "$user_id" "$msg_str"
  done
}

###--------------------------------------------------------------------------------------------
## 开始执行脚本
check_command "curl" "jq"
readonly R_SHORT_OPTIONS=""
readonly R_LONG_OPTIONS="$R_PARAM_APP_ID:,$R_PARAM_APP_SECRET:,$R_PARAM_EMAILS:,$R_PARAM_MSG:"
if ! parameters=$(getopt -o "$R_SHORT_OPTIONS" -l "$R_LONG_OPTIONS" -n "$0" -- "$@"); then
  exit 1
fi
eval set -- "$parameters"

# 循环解析位置参数
while true; do
  case "$1" in
  "--$R_PARAM_APP_ID")
    app_id=$2
    [[ "${app_id:0:1}" == "-" ]] && error_log "Invalid param '$app_id' for '--$R_PARAM_APP_ID'"
    shift 2
    ;;
  "--$R_PARAM_APP_SECRET")
    app_secret=$2
    [[ "${app_secret:0:1}" == "-" ]] && error_log "Invalid param '$app_secret' for '--$R_PARAM_APP_SECRET'"
    shift 2
    ;;
  "--$R_PARAM_EMAILS")
    emails=$2
    [[ "${emails:0:1}" == "-" ]] && error_log "Invalid param '$emails' for '--$R_PARAM_EMAILS'"
    shift 2
    ;;
  "--$R_PARAM_MSG")
    msg=$2
    [[ "${msg:0:1}" == "-" ]] && error_log "Invalid param '$msg' for '--$R_PARAM_MSG'"
    shift 2
    ;;
  --)
    shift
    action=$1
    shift
    break
    ;;
  *)
    echo "Unknown Error"
    exit 1
    ;;
  esac
done

[ -z "$action" ] && action=$R_ACTION_DEFAULT

# 默认参数设置
[ -z "$check_interval" ] && check_interval=$R_DEFAULT_VALUE_CHECK_INTERVAL

## 脚本开始执行，执行具体的action
eval "case $action in
$R_ACTIONS_IN_CASE)
  \"action_${action//-/_}\"
  exit 0
  ;;
*)
  echo \"Unknown action: $action, support actions: $R_ACTIONS\"
  exit 1
  ;;
esac"

