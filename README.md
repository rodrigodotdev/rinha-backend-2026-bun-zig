# Rinha de Backend 2026 - Bun + Zig

Esta é minha submissão para a [Rinha de Backend 2026](https://github.com/zanfranceschi/rinha-de-backend-2026), focada em detecção de fraude por busca vetorial.

O objetivo da implementação é manter o caminho quente o menor possível: Bun recebe a requisição HTTP, repassa o corpo bruto para Zig via FFI, e Zig faz parse, vetorização e busca no índice em memória.

## Tecnologias

- **[Bun](https://bun.sh)** - runtime HTTP e compilação standalone.
- **[Zig](https://ziglang.org)** - parser JSON, vetorização, índice e busca vetorial.
- **[HAProxy](https://www.haproxy.org)** - load balancer round-robin.
- **Docker** - imagem final com binário, `libfraud.so` e `fraud-index.bin`.
- **IVF + mmap** - índice vetorial pré-processado e carregado como arquivo mapeado.

## Arquitetura

```text
client
  -> HAProxy :9999
    -> api-1.sock / api-2.sock
      -> Bun
        -> Zig libfraud.so
          -> mmap IVF index
```

O `docker-compose.yml` local sobe:

- `lb`: HAProxy na porta `9999`.
- `api-1`: instância Bun usando `/run/sock/api-1.sock`.
- `api-2`: instância Bun usando `/run/sock/api-2.sock`.

Limites declarados:

| Serviço | CPU | Memória |
| --- | ---: | ---: |
| `api-1` | `0.4` | `150M` |
| `api-2` | `0.4` | `150M` |
| `lb` | `0.2` | `30M` |
| **Total** | **1.0** | **330M** |

## Estratégia

- Bun não faz `JSON.parse` no endpoint principal.
- A FFI chama `fraud_score_json(ptr, len)` uma vez por requisição.
- Zig extrai os campos necessários do payload esperado da Rinha.
- O vetor final tem 14 dimensões, seguindo as regras oficiais.
- A busca usa IVF com `k=4096`, `nprobe=10` e fallback `nprobe=16` quando a decisão cai perto do limite.
- A resposta HTTP usa corpos JSON pré-computados para os 6 scores possíveis.

Falhas de parse ou falhas nativas retornam uma resposta válida e rápida:

```json
{"approved":true,"fraud_score":0.0}
```

## Endpoints

### `GET /ready`

Health check usado pela engine da Rinha.

```json
{"status":"ok"}
```

### `POST /fraud-score`

Recebe uma transação e retorna a decisão de fraude.

```json
{
  "approved": false,
  "fraud_score": 0.8
}
```

## Como executar

O build Docker baixa o `references.json.gz` do repositório oficial, gera a shared library em Zig, constrói o índice e compila o servidor Bun standalone.

Por padrão, o arquivo de referência vem da branch `main` da Rinha:

```text
https://raw.githubusercontent.com/zanfranceschi/rinha-de-backend-2026/main/resources/references.json.gz
```

Suba a stack local:

```bash
docker compose up --build -d
curl -fsS http://localhost:9999/ready
```

Para fixar outro commit, branch ou tag do repositório oficial:

```bash
RINHA_REF=<commit-ou-tag> docker compose up --build -d
```

Pare a stack:

```bash
docker compose down
```

## Scripts

```bash
# Typecheck + build standalone Bun
bun run check

# Publica a imagem linux/amd64 usada na submissão
RINHA_API_IMAGE=docker.io/rodrigodotdev/rinha-backend-2026-bun-zig:latest scripts/publish-image.sh

# Gera os arquivos finais da branch submission
scripts/prepare-submission.sh
```

## Configuração

| Variável | Padrão | Descrição |
| --- | --- | --- |
| `RINHA_REF` | `main` | Ref do repositório oficial usado para baixar `references.json.gz` |
| `RINHA_API_IMAGE` | `docker.io/rodrigodotdev/rinha-backend-2026-bun-zig:latest` | Imagem pública usada no compose de submissão |
| `NATIVE_TARGET` | `x86_64-linux-gnu` | Target Zig |
| `NATIVE_CPU` | `haswell` | CPU alvo do binário nativo |
| `FAST_NPROBE` | `10` | Número de listas IVF no primeiro passe |
| `FULL_NPROBE` | `16` | Número de listas IVF no fallback |
| `INDEX_K` | `4096` | Quantidade de centróides |
| `INDEX_ITERATIONS` | `25` | Iterações do k-means |
| `INDEX_SAMPLE` | `262144` | Amostra usada no treinamento |
| `WARMUP_ROUNDS` | `16` | Chamadas locais de aquecimento por instância |

## Submissão

A branch `submission` deve conter apenas os arquivos necessários para a engine:

```text
docker-compose.yml
haproxy.cfg
info.json
```

O arquivo `docker-compose.submission.yml` referencia a imagem pública e não faz build local. O script abaixo copia os arquivos com os nomes esperados pela Rinha:

```bash
scripts/prepare-submission.sh
```

---

Desenvolvido por [@rodrigodotdev](https://github.com/rodrigodotdev).
