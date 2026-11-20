# KAIROS-BASES

Repositório oficial de distribuição das bases de dados de referência de custos para o **Kairos** (SINAPI, SICRO, ORSE, SEINFRA, CDHU e estaduais), pré-convertidas em bancos **SQLite + FTS5** compactados (`.db.gz`).

---

## Política de Retenção (Últimos 6 Meses + Mês Vigente)

Para manter o repositório enxuto e rápido:
- Ficam disponíveis para download direto em nuvem apenas as bases do **mês vigente e dos últimos 6 meses** (janela móvel de 7 competências).
- Competências anteriores à janela de 6 meses são removidas automaticamente das **GitHub Releases** e do `catalog-index.json` (workflow mensal em `.github/workflows/retention-cleanup.yml`).
- Caso um projeto precise de uma competência mais antiga, o usuário pode importá-la localmente no **Kairos** através de **Pasta Monitorada** ou **Importar Arquivo** (`.zip` / `.xlsx`).

---

## Estrutura do Repositório

```text
KAIROS-BASES/
├── README.md                                 # Documentação e guia de publicação
├── .gitignore                                # Impede envio de .db, .xlsx e .zip nos commits
├── catalog-index.json                        # Índice mestre lido pelo Kairos (releases, UFs e URLs)
├── scripts/
│   └── publicar-release.ps1                  # Compacta .db -> .db.gz e atualiza catalog-index.json
└── .github/
    └── workflows/
        └── retention-cleanup.yml             # Limpa releases > 6 meses automaticamente todo dia 05
```

### Convenção das Releases e Arquivos
Os arquivos pesados **não ficam nos commits do Git**, mas sim anexados como *Assets* em **Releases**:
- **Tag da Release:** `{fonte}-{AAAA}-{MM}` (ex.: `sinapi-2026-10`, `sicro-2026-09`)
- **Arquivo do Asset:** `{FONTE}_{UF}_{AAAA}-{MM}_{REGIME}.db.gz`
  - `SD` = Não Desonerado
  - `CD` = Desonerado
  - Exemplo: `SINAPI_SP_2026-10_SD.db.gz`

Cada `.db.gz` contém composições sintéticas, CPUs analíticas, índice FTS5 e insumos (`resources`).

---

## Como Inserir e Publicar Novas Bases

1. Converta as planilhas desejadas (`.xlsx` / `.zip`) para `.db` na pasta local `Documentos\Kairos\Bases_de_Dados\{FONTE}\`.
2. Execute o script de empacotamento na raiz deste repositório:

```powershell
# Apenas compacta para .db.gz e atualiza o catalog-index.json localmente:
.\scripts\publicar-release.ps1 -Source sinapi -Period 2026-10

# Ou, com GitHub CLI (gh) autenticado, publica a Release e aplica a janela de 6 meses:
.\scripts\publicar-release.ps1 -Source sinapi -Period 2026-10 -Publish
```

3. Se optar por publicar manualmente no navegador:
   - Suba o `catalog-index.json` atualizado via `git push`;
   - Acesse **Releases → Draft a new release** no GitHub, crie a tag (ex.: `sinapi-2026-10`), arraste os arquivos `.db.gz` gerados na pasta `dist_releases\sinapi-2026-10\` e clique em **Publish release**.
