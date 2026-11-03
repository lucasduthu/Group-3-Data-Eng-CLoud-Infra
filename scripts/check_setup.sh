#!/usr/bin/env bash
# Vérifie que la machine est prête pour le projet (Groupe 3).
# Usage : bash scripts/check_setup.sh
# Ne crée rien et ne modifie rien.

ok()   { printf "  \033[32mOK\033[0m   %s\n" "$1"; }
ko()   { printf "  \033[31mKO\033[0m   %s  →  %s\n" "$1" "$2"; FAIL=1; }
FAIL=0

echo "Outils"
command -v brew      >/dev/null && ok "Homebrew"            || ko "Homebrew" "installer depuis https://brew.sh"
command -v git       >/dev/null && ok "git $(git --version | awk '{print $3}')" || ko "git" "brew install git"
command -v gh        >/dev/null && ok "GitHub CLI"          || ko "GitHub CLI" "brew install gh"
command -v gcloud    >/dev/null && ok "gcloud"              || ko "gcloud" "brew install --cask google-cloud-sdk, puis nouveau Terminal"
command -v docker    >/dev/null && ok "docker"              || ko "docker" "brew install --cask docker, puis ouvrir Docker Desktop"
command -v terraform >/dev/null && ok "terraform"           || ko "terraform" "brew tap hashicorp/tap && brew install hashicorp/tap/terraform"
command -v python3.12 >/dev/null && ok "python 3.12"        || ko "python 3.12" "brew install python@3.12"

echo "Comptes"
GH_USER=$(gh api user --jq .login 2>/dev/null)
[ -n "$GH_USER" ] && ok "GitHub connecté : $GH_USER" || ko "GitHub" "gh auth login"
GIT_EMAIL=$(git config --global user.email)
[ -n "$GIT_EMAIL" ] && ok "git user.email = $GIT_EMAIL (doit être un e-mail de ton compte GitHub)" || ko "git user.email" "git config --global user.email \"ton-email-github\""
ACCOUNT=$(gcloud config get-value account 2>/dev/null)
[ -n "$ACCOUNT" ] && ok "gcloud connecté : $ACCOUNT" || ko "gcloud" "gcloud auth login"
PROJECT_SET=$(gcloud config get-value project 2>/dev/null)
[ "$PROJECT_SET" = "albert-de-msc2-26-g03" ] && ok "projet GCP : $PROJECT_SET" || ko "projet GCP ($PROJECT_SET)" "gcloud config set project albert-de-msc2-26-g03"
gcloud auth application-default print-access-token >/dev/null 2>&1 && ok "credentials Python/dbt/Terraform" || ko "credentials applicatifs" "gcloud auth application-default login"

echo "Docker"
docker info >/dev/null 2>&1 && ok "Docker Desktop tourne" || ko "Docker Desktop" "ouvrir l'application Docker"

echo "Python du projet"
if [ -x "$HOME/albert-de/bin/python" ]; then
  "$HOME/albert-de/bin/python" -c "import pandas, pyarrow" 2>/dev/null \
    && ok "venv ~/albert-de avec pandas et pyarrow" \
    || ko "pandas/pyarrow" "source ~/albert-de/bin/activate && python -m pip install pandas pyarrow"
else
  ko "venv ~/albert-de" "python3.12 -m venv ~/albert-de"
fi

echo "Repo"
[ -d "$HOME/Group-3-Data-Eng-CLoud-Infra/.git" ] && ok "repo cloné dans ~/Group-3-Data-Eng-CLoud-Infra" || ko "repo" "cd ~ && gh repo clone lucasduthu/Group-3-Data-Eng-CLoud-Infra"

echo "Variables (~/.zshrc)"
[ "$BUCKET" = "gs://albert-de-msc2-26-g03-bronze" ] && ok "\$BUCKET" || ko "\$BUCKET" "voir la section 6 du guide d'initialisation, puis source ~/.zshrc"

echo
[ $FAIL -eq 0 ] && echo "Tout est prêt." || echo "Corrige les lignes KO, puis relance ce script."
