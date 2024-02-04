## 使用eval创建动态的变量, 仅适用于简单变量
# $1: 变量名称
# $2: 变量值
create_dynamic_var() {
  local name="$1"
  local value="$2"
  # 需要将"-"转换成"_"
  name="${name//-/_}"
  # 需要将"""转换成"\""
  value="${value//\"/\\\"}"
  # 加上双引号, 解决字符串带有空格报错的问题
  eval "$name=\"$value\""
}

## 获取简单变量
# $1: 变量名称
get_dynamic_var() {
  local name="$1"
  # 需要将"-"转换成"_"
  name="${name//-/_}"
  get_var "$name"
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

