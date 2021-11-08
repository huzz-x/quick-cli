#!/bin/bash

readonly R_GITLAB_BASEURL="https://git.example.cn"
readonly R_GITLAB_API_BASEURL="$R_GITLAB_BASEURL/api/v4"
readonly R_BUILD_PROJECT_TRIGGER_NAME="build-project"

## Pipeline Status
readonly R_PIPELINE_STATUS_PENDING="pending"
readonly R_PIPELINE_STATUS_RUNNING="running"
readonly R_PIPELINE_STATUS_SUCCESS="success"
readonly R_PIPELINE_STATUS_FAILED="failed"
readonly R_PIPELINE_STATUS_CANCELED="canceled"

# shellcheck disable=SC2034
readonly R_PARAM_ACCESS_TOKEN_DESCRIPTION="访问Gitlab的Access Token, 必须有api权限"
# shellcheck disable=SC2034
readonly R_PARAM_CHECK_INTERVAL_DESCRIPTION="轮询Pipeline状态的时间间隔, 单位秒, 默认10秒"
# shellcheck disable=SC2034
readonly R_PARAM_PROJECT_ID_DESCRIPTION="Gitlab项目的ID, 可以在Gitlab项目的主页看到"
# shellcheck disable=SC2034
readonly R_PARAM_PROJECT_PIPELINE_IDS_DESCRIPTION="要同步等待结束的Pipeline的描述串, 格式: <project_id>#<pipeline_id>,<pipeline_id>, 多个Project以#分隔, 多个PipelineID以,分隔, 例如: '539#2070,2072 540#207'"
# shellcheck disable=SC2034
readonly R_PARAM_REF_DESCRIPTION="传递给Pipeline Trigger的参数, 待触发的Pipeline所在的分支"
# shellcheck disable=SC2034
readonly R_PARAM_TRIGGER_PARAMS_DESCRIPTION="传递给Pipeline的参数"

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
  printf "%s %s\n\n" "gitlab-cli" "$action"
  printf "%s\n" "requires:"
  for param in "${params[@]}"; do
    var_name="R_PARAM_$(echo "${param^^}" | tr '-' '_')_DESCRIPTION"
    printf "  %-${indent}s %s\n" "--$param" "$(get_var "$var_name")"
  done
  if [ -z "$options_str" ]; then
    return
  fi
  echo
  IFS="," read -r -a option_params_arr <<< "$options_str"
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
  if [ " -h -- '${action}'" == "$parameters" ] || [ " --help -- '${action}'" == "$parameters" ]; then
    explain_action_with_param "$action" "${to_checks[@]}"
    exit 0
  fi
  local param
  local required_param=""
  for param in "${to_checks[@]}"; do
    echo "$parameters" | grep "'$action'" | grep -v "\-\-$param" > /dev/null && required_param=$(append "${required_param}" "--${param}")
  done
  [[ -n "${required_param}" ]] && error_log "Action '$action' requires ${required_param} param."
}

action_params_check_fire_trigger() {
  options_str=""
  check_action_param fire-trigger access-token project-id ref
}

action_params_check_sync() {
  options_str="check-interval"
  check_action_param sync access-token project-pipeline-ids
}

## 清空console
# $1: Len
clear_console() {
  local -r len=100
  printf "%${len}s\r" ""
}

## 创建一个临时的Pipeline Trigger, Trigger的id存放在<trigger_id>变量中, token存放在<trigger_token>变量中
# $1: Project ID
# $2: 触发器的描述
create_pipeline_trigger() {
  local project_id="$1"
  [[ -z "$project_id" ]] && error_log "project_id不允许为空."
  local description="$2"
  [[ -z "$project_id" ]] && error_log "description不允许为空."
  info_log "创建Pipeline Trigger, Project ID: ${project_id}, description: ${description}"
  local -r res=$(curl --location --request POST -s -w "\n%{http_code}" \
    "${R_GITLAB_API_BASEURL}/projects/${project_id}/triggers?description=${description}" \
    --header "private-token: ${access_token}")
  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  [[ $res_ret_code != 201 ]] && error_log "创建Pipeline Trigger失败. Project ID: ${project_id}. response code: ${res_ret_code}, body: ${res_ret_body}"
  # 记录下Pipeline ID和Token
  trigger_id=$(echo "$res_ret_body" | jq -r ".id")
  info_log "Trigger ID: ${trigger_id}"
  trigger_token=$(echo "$res_ret_body" | jq -r ".token")
}

## 根据描述获取指定Project ID的Pipeline Trigger, 如果获取不到则创建一个并将对应的值设置到<trigger_id>和<trigger_token>变量中
# $1: Project ID
# $2: 触发器的描述
get_pipeline_trigger() {
  local project_id="$1"
  [[ -z "$project_id" ]] && error_log "project_id不允许为空."
  local description="$2"
  [[ -z "$project_id" ]] && error_log "description不允许为空."
  local -r res=$(curl --location --request GET -s -w "\n%{http_code}" \
    "${R_GITLAB_API_BASEURL}/projects/${project_id}/triggers" \
    --header "private-token: ${access_token}")
  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  [[ $res_ret_code != 200 ]] && error_log "获取Pipeline Trigger失败. Project ID: ${project_id}. response code: ${res_ret_code}, body: ${res_ret_body}"
  trigger_id=$(echo "$res_ret_body" | sed -e "s/.*\"id\":\(.*\),.*,\"description\":\"${description}\",.*/\1/" | grep -v "token" | grep -v "\[\]")
  if [[ -z "$trigger_id" ]]; then
    # Trigger不存在, 创建一个
    info_log "Project ID为[${project_id}]的项目不存在描述为[${description}]的Pipeline Trigger, 开始创建Pipeline Trigger."
    create_pipeline_trigger "$project_id" "$description"
  else
    trigger_token=$(echo "$res_ret_body" | sed -e "s/.*\"token\":\"\(.*\)\",.*\"description\":\"${description}\",.*/\1/" | grep -v "token")
  fi
}

## 获取Pipeline状态, 被设置在<pipeline_status_json>变量中
# $1: Project ID
# $2: Pipeline ID
get_pipeline_status() {
  local project_id="$1"
  [[ -z "$project_id" ]] && error_log "project_id不允许为空."
  local pipeline_id="$2"
  [[ -z "$pipeline_id" ]] && error_log "pipeline_id不允许为空."
  local -r res=$(curl --location --request GET -s -w "\n%{http_code}" \
    "${R_GITLAB_API_BASEURL}/projects/${project_id}/pipelines/${pipeline_id}" \
    --header "private-token: ${access_token}")
  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  [[ $res_ret_code != 200 ]] && error_log "获取Pipeline状态失败. Project ID: ${project_id}. Pipeline ID: ${pipeline_id}, response code: ${res_ret_code}, body: ${res_ret_body}"
  pipeline_status_json="$res_ret_body"
}

action_fire_trigger() {
  # 将trigger_params转成url参数, "hh=123 xx=456" ==> variables[hh]=123&variables[xx]=456
  local trigger_param_arr
  local trigger_param
  local variables
  local key
  local value
  IFS=" " read -r -a trigger_param_arr <<< "$trigger_params"
  for trigger_param in "${trigger_param_arr[@]}"; do
    key=$(echo "$trigger_param" | cut -d= -f1)
    value=$(echo "$trigger_param" | cut -d= -f2)
    variables=$(append "$variables" "variables[$key]=$value" "&")
  done

  # 特殊字符转换
  variables="${variables//#/%23}"

  get_pipeline_trigger "$project_id" $R_BUILD_PROJECT_TRIGGER_NAME
  [[ -z "$project_id" ]] && error_log "project_id不允许为空."
  [[ -z "$trigger_token" ]] && error_log "trigger_token不允许为空."

  # 一定要加g参数
  local -r res=$(curl -X POST -g -s -w "\n%{http_code}" \
     "${R_GITLAB_API_BASEURL}/projects/${project_id}/trigger/pipeline?token=${trigger_token}&ref=${ref}&${variables}")
  local -r res_ret_code=$(echo "$res" | tail -1)
  local -r res_ret_body=$(echo "$res" | head -1)
  [[ $res_ret_code != 201 ]] && error_log "触发Pipeline Trigger失败. Project ID: ${project_id}, Trigger ID: ${trigger_id}, Trigger Token: ${trigger_token}. response code: ${res_ret_code}, body: ${res_ret_body}"
  echo "$res_ret_body"
}

action_sync() {
  local project_pipeline_id_arr
  local pipeline_id_arr
  IFS=" " read -r -a project_pipeline_id_arr <<< "$project_pipeline_ids"
  local project_id
  local pipeline_ids
  local success_pipeline_count=0
  local total_pipeline_count=0

  ## 循环一轮计算Pipeline总数, 打印Pipeline
  for project_pipeline_id in "${project_pipeline_id_arr[@]}"; do
    pipeline_ids=$(echo "$project_pipeline_id" | cut -d# -f2)
    IFS="," read -r -a pipeline_id_arr <<< "$pipeline_ids"
    for pipeline_id in "${pipeline_id_arr[@]}"; do
      total_pipeline_count=$((total_pipeline_count+1))
    done
  done
  info_log "Total Pipeline: $total_pipeline_count"

  local web_url
  local status
  local pipeline_has_failure
  local log_buf
  local status_color
  local success_pipeline_str=""
  while [ $success_pipeline_count -ne $total_pipeline_count ]; do
    # 清空
    log_buf=""
    for project_pipeline_id in "${project_pipeline_id_arr[@]}"; do
      project_id=$(echo "$project_pipeline_id" | cut -d# -f1)
      pipeline_ids=$(echo "$project_pipeline_id" | cut -d# -f2)
      IFS="," read -r -a pipeline_id_arr <<< "$pipeline_ids"
      for pipeline_id in "${pipeline_id_arr[@]}"; do
        get_pipeline_status "$project_id" "$pipeline_id"
        web_url="$(echo "$pipeline_status_json" | jq -r .web_url)"
        status="$(echo "$pipeline_status_json" | jq -r .status)"
        case $status in
        "$R_PIPELINE_STATUS_PENDING")
          status_color="$R_COLOR_Y"
        ;;
        "$R_PIPELINE_STATUS_RUNNING")
          status_color="$R_COLOR_G"
          ;;
        "$R_PIPELINE_STATUS_SUCCESS")
          if ! echo ",${success_pipeline_str}," | grep -q ",${pipeline_id},"; then
            success_pipeline_count=$((success_pipeline_count+1))
            success_pipeline_str="${success_pipeline_str},${pipeline_id}"
          fi
          status_color="$R_COLOR_G"
          ;;
        "$R_PIPELINE_STATUS_FAILED" | "$R_PIPELINE_STATUS_CANCELED")
          ## 如果Pipeline失败或者取消, 设置错误标志
          pipeline_has_failure="true"
          status_color="$R_COLOR_R"
          ;;
        esac
        log_buf="[${status_color}${status}${R_RESET}]${web_url} $log_buf"
      done
    done

    if [ $success_pipeline_count -eq "$total_pipeline_count" ]; then
      ## 不要加\r, 避免看不到最终结果
      echo -ne "Status[$success_pipeline_count/$total_pipeline_count]: ${log_buf}\n"
    else
      if [ "$pipeline_has_failure" == "true" ]; then
        ## 不要加\r, 避免看不到哪个Pipeline失败了
        echo -ne "Status[$success_pipeline_count/$total_pipeline_count]: ${log_buf}\n"
        error_log "存在失败或取消的Pipeline, 打包异常终止, 请检查Pipeline状态"
      else
        if [ -n "$CI_PROJECT_ID" ]; then
          # CI环境下, \r输出不了, 采用常规的滚动输出(在命令行下, 采用覆盖式输出)
          echo -e "Status[$success_pipeline_count/$total_pipeline_count]: ${log_buf}"
        else
          clear_console
          echo -ne "Status[$success_pipeline_count/$total_pipeline_count]: ${log_buf}\r"
        fi
        sleep "$check_interval"
      fi
    fi
  done
}

action_help() {
  printf "%s\n  %s\n\n" "名称:" "gitlab-cli"
  printf "%s\n  %s\n\n" "版本:" ""
  printf "%s\n  %s\n\n" "Actions:" "help,fire-trigger,sync"
  explain_action "fire-trigger" "触发指定项目的Pipeline" "gitlab-cli fire-trigger --project-id=539 --access-token=<access_token> --ref=master --trigger-params='hh=123 xx=456'"
  explain_action "sync" "同步等待指定的Pipeline结束" "gitlab-cli sync --project-pipeline-ids='539#2070,2072 540#2073' --access-token=<access_token> --check-interval=10"
}

## shell执行的核心部分
readonly R_LONG_OPTIONS="access-token:,check-interval:,project-id:,project-pipeline-ids:,ref:,trigger-params:,help"
readonly R_SHORT_OPTIONS=",h"
readonly R_TOOL_ACTIONS="help,fire-trigger,sync"
if ! parameters=$(getopt -o "$R_SHORT_OPTIONS" -l "$R_LONG_OPTIONS" -n "$0" -- "$@"); then
  exit 1
fi
eval set -- "$parameters"

while true; do
  case "$1" in
  "--access-token")
    access_token="$2"
    shift 2
    ;;
  "--check-interval")
    check_interval="$2"
    shift 2
    ;;
  "--project-id")
    project_id="$2"
    shift 2
    ;;
  "--project-pipeline-ids")
    project_pipeline_ids="$2"
    shift 2
    ;;
  "--ref")
    ref="$2"
    shift 2
    ;;
  "--trigger-params")
    trigger_params="$2"
    shift 2
    ;;
  "--help" | "-h")
    shift 1
    ;;
  --)
    shift
    action=$1
    echo "$R_TOOL_ACTIONS" | grep -q "$action" || error_log "Unsupported action: $action, available actions: $R_TOOL_ACTIONS"
    shift
    break
    ;;
  *)
    echo "Unknown Error: $1"
    exit 1
    ;;
  esac
done


if [ -z "$action" ]; then
  action="help"
else
  eval "action_params_check_${action//-/_}"
fi
## 脚本开始执行，执行具体的action
eval "action_${action//-/_}"

