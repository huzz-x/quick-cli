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

