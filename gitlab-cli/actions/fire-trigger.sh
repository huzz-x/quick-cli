fire_trigger() {
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