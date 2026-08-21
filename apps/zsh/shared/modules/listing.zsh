# ==============================================================================
# 终端列表显示
#
# 纯文本输出或复杂参数直接交给系统 ls，避免破坏脚本和管道。
# ==============================================================================

unalias ls 2>/dev/null || true

function ls() {
  emulate -L zsh -o extended_glob

  local arg
  local -a ls_args
  local skipped_end_options=0
  for arg in "$@"; do
    if (( ! skipped_end_options )) && [[ "$arg" == "--" ]]; then
      skipped_end_options=1
      continue
    fi
    if (( skipped_end_options )) && [[ "$arg" == -* ]]; then
      ls_args+=("./$arg")
    else
      ls_args+=("$arg")
    fi
  done

  if [[ ! -t 1 ]]; then
    command ls "${ls_args[@]}"
    return
  fi

  local opt
  local operands=0
  local passthrough=0
  local end_options=0

  for arg in "$@"; do
    if (( ! end_options )) && [[ "$arg" == "--" ]]; then
      end_options=1
      continue
    fi
    if (( ! end_options )) && [[ "$arg" == --* ]]; then
      passthrough=1
      break
    fi
    if (( ! end_options )) && [[ "$arg" == -?* ]]; then
      opt=${arg#-}
      [[ "$opt" == *[1CglmnoORsx]* ]] && passthrough=1
      continue
    fi
    (( operands++ ))
  done

  # macOS 的 BSD ls 不把 `--` 当作通用选项终止符。上面的归一化会移除
  # 终止符，并把后续以 - 开头的相对路径改成 ./path 再交给系统 ls。
  if (( passthrough || operands > 1 )); then
    command ls "${ls_args[@]}"
    return
  fi

  local -a color_flags
  if [[ "$OSTYPE" == darwin* ]]; then
    color_flags=(-G)
  elif command ls --color=auto >/dev/null 2>&1; then
    color_flags=(--color=auto)
  fi

  local output
  output=$(CLICOLOR_FORCE=1 command ls -1 "${color_flags[@]}" "${ls_args[@]}") || return

  local -a items widths col_widths best_widths
  local line plain
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    items+=("$line")
    plain=${line//$'\e'\[[0-9;]#m/}
    widths+=(${#plain})
  done <<< "$output"

  local count=${#items}
  (( count )) || return 0

  local min_gap=$ZSH_LISTING_MIN_GAP
  local term_cols=${COLUMNS:-0}
  if (( term_cols <= 0 )); then
    term_cols=$(tput cols 2>/dev/null || print 80)
  fi

  local best_cols=1
  local cols col row idx total pad
  for (( cols = count; cols >= 1; cols-- )); do
    col_widths=()
    for (( col = 1; col <= cols; col++ )); do
      col_widths[$col]=0
    done
    for (( idx = 1; idx <= count; idx++ )); do
      col=$(( (idx - 1) % cols + 1 ))
      (( widths[$idx] > col_widths[$col] )) && col_widths[$col]=${widths[$idx]}
    done
    total=$(( min_gap * (cols - 1) ))
    for (( col = 1; col <= cols; col++ )); do
      (( total += col_widths[$col] ))
    done
    if (( total <= term_cols )); then
      best_cols=$cols
      best_widths=("${col_widths[@]}")
      break
    fi
  done

  local rows=$(( (count + best_cols - 1) / best_cols ))
  for (( row = 0; row < rows; row++ )); do
    for (( col = 1; col <= best_cols; col++ )); do
      idx=$(( row * best_cols + col ))
      (( idx > count )) && break
      print -rn -- "${items[$idx]}"
      if (( col < best_cols && idx < count )); then
        pad=$(( best_widths[$col] - widths[$idx] + min_gap ))
        printf '%*s' "$pad" ''
      fi
    done
    print
  done
}
