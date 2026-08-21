# 非 login 的交互式 Zsh 也能加载 NVM。

export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]] && (( ! $+functions[nvm] )); then
  source "$NVM_DIR/nvm.sh"
fi
