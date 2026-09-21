# Spur — Simple Portable Universal Runner

**Data:** 2026-09-21
**Status:** Design aprovado, pronto para plano de implementação
**Organização:** [Esliph](https://github.com/esliph)

## Resumo

`spur` é um task runner escrito em POSIX sh estrito. Ele lê um arquivo `Spurfile`,
lista tarefas e executa cada uma num único shell, com passthrough de argumentos.

O diferencial é a ausência de runtime: não há binário a compilar, nem Go, Rust ou
Node a instalar. O programa é um script shell que roda em qualquer Unix — incluindo
containers Alpine mínimos, onde `just` e Task exigem binário e o `make` nem sempre
está presente.

O escopo é deliberadamente menor que o do `make`: **Spur é um executor de tarefas,
não um sistema de build.** Não há grafo de dependências, não há rebuild incremental
por timestamp, não há regras de padrão.

## Decisões fundamentais

| Decisão | Escolha |
|---|---|
| Forma de distribuição | Script instalado no PATH (ou copiado para dentro do repositório) |
| Dialeto | POSIX sh estrito — dash, ash, busybox, bash, zsh, ksh |
| Modelo de execução | Sem dependências entre tarefas; chamada explícita `spur outra` |
| Formato do Spurfile | Sintaxe make-like com parser próprio |
| Entrada do usuário | Passthrough posicional via `"$@"` |
| Estado compartilhado | Preâmbulo shell no topo do arquivo |
| Motor | `awk` extrai o bloco, `sh -c` executa |

## 1. O que entra e o que sai do Make

### Entra do Make

| Recurso | Forma no Spur |
|---|---|
| Regra nomeada + receita | `nome: ## descrição` seguido de bloco indentado |
| `make <alvo>` | `spur <tarefa>` |
| Auto-doc por comentário `##` | Promovida de convenção a recurso: alimenta o `--list` |
| `make -n` | `spur -n` imprime o script montado em vez de executar |
| `make -f` | `spur -f outro.Spurfile` |
| `make -C dir` | `spur -C dir tarefa` |

### Entra, que o Make não tem

| Recurso | Motivo |
|---|---|
| Passthrough `"$@"` | `spur test -k foo -vv`. Impossível no make. |
| Preâmbulo shell | Substitui variáveis, condicionais e `include` com um mecanismo só |
| Busca ascendente do Spurfile | `spur test` funciona de qualquer subpasta, como o `git` |
| `set -e` no bloco | Restaura o abort-on-error que o make dava via shell-por-linha |
| Guarda de recursão | Impede que chamadas encadeadas virem fork bomb |
| Função `spur` injetada | Chamadas encadeadas funcionam mesmo com o runner fora do PATH |

### Sai — o motor de build

| Recurso | Razão |
|---|---|
| Pré-requisitos (`alvo: deps`) | Trocados por chamada explícita, para que o passthrough de argumentos permaneça simétrico e visível |
| Rebuild incremental por timestamp | `stat` diverge entre GNU/BSD/busybox; `-nt` não é POSIX. O recurso mais caro e o menos usado em Makefile-como-task-runner |
| Execução paralela (`-j`) | Sem grafo, não há o que paralelizar com segurança |
| Regras de padrão (`%.o: %.c`) | Dependem de alvos-arquivo, que não existem |
| Regras implícitas embutidas | Spur não sabe compilar nada, e é isso que o torna previsível |
| Variáveis automáticas (`$@`, `$<`, `$^`) | Não há pré-requisitos a referenciar. Libera `$@` com a semântica shell (os argumentos) |
| `include`, condicionais (`ifeq`) | O preâmbulo tem `.` e `if` de verdade |
| Recursão via `$(MAKE)` | `spur -C sub build` é mais claro |

### Sai — as pegadinhas

| Pegadinha | Substituto |
|---|---|
| TAB obrigatório | Indentação por espaços; TAB aceito, nunca exigido |
| Um shell novo por linha de receita | Bloco inteiro num só `sh`: `cd` e variáveis persistem |
| `$$` para escapar `$` | O runner não expande nada; `$` chega intacto ao shell |
| `.PHONY` | Toda tarefa é phony por construção — o conceito deixa de existir |
| `@` por linha (silenciar) | Não implementável (ver Limitações). Eco é desligado por padrão; `-x` liga |
| `-` por linha (ignorar erro) | `\|\| true` |
| Eco de comandos por padrão | Desligado. `spur -x` liga `set -x` com `PS4` enxuto |

## 2. A linguagem do Spurfile

```sh
# Tudo antes da primeira tarefa é preâmbulo: shell puro,
# injetado no topo de toda tarefa executada.
IMAGE=myapp:latest
: "${ENV:=dev}"
[ -f .env ] && . ./.env

_log() { printf '>> %s\n' "$1"; }

build: ## constrói a imagem
  _log "building $IMAGE"
  docker build -t "$IMAGE" .

test: ## roda os testes
  spur build
  pytest -q "$@"

db-reset: ## recria o banco (destrutivo)
  dropdb --if-exists app && createdb app
```

### Gramática

1. Uma linha que casa `^[A-Za-z0-9_.-]+:` abre uma tarefa. O corpo vai até a próxima
   linha não-indentada e não-vazia.
2. `## texto` no cabeçalho é a descrição, usada pelo `--list`. Sem `##`, a tarefa
   existe e é executável, apenas aparece sem descrição.
3. O corpo é indentado. Espaços são a forma canônica; TAB é aceito e tratado como
   indentação, nunca exigido.
4. **Dedent:** antes de executar, o runner remove de todas as linhas do corpo a menor
   indentação comum entre elas (linhas vazias não contam para o cálculo). Isso preserva
   a indentação relativa de `if`, `for` e heredocs.
5. **Linhas vazias dentro do corpo pertencem ao corpo** e não o encerram. Só uma linha
   com conteúdo na coluna zero fecha a tarefa.
6. Tudo antes da primeira tarefa é preâmbulo.
7. Uma linha não-indentada que não casa o padrão de tarefa e aparece **depois** da
   primeira tarefa é erro de sintaxe (código 65). Antes da primeira tarefa, é preâmbulo.

### Propriedades

- **Nome de tarefa aceita `-` e `.`** (`db-reset`, `docker.build`), porque tarefas
  não são funções shell — o corpo é extraído como texto.
- **Nenhuma expansão pelo runner.** O corpo vai literal para o `sh`: `$IMAGE`,
  `$(date)`, `${x:-y}`, `$$` (PID) têm semântica shell padrão.
- **Tarefa sem `##` continua executável.** Documentação não é requisito sintático.

## 3. Modelo de execução

### Pipeline de `spur test -k foo`

```
1. Parse dos argumentos      -> flags do runner, nome da tarefa, resto = "$@"
2. Localiza o Spurfile       -> -f, ou -C dir, ou busca ascendente
3. cd na raiz do Spurfile    -> cwd determinístico
4. Guarda de recursão        -> SPUR_STACK contém "test"? aborta
5. awk extrai                -> preâmbulo + corpo da tarefa
6. Monta o script            -> prelúdio do runner + preâmbulo + corpo
7. sh -c "$script" "spur test" -k foo
8. Propaga o exit code
```

### O script montado

```sh
set -e                                  # prelúdio do runner
spur() { "$SPUR_BIN" "$@"; }            # prelúdio do runner
IMAGE=myapp:latest                      # preâmbulo do usuário
_log() { printf '>> %s\n' "$1"; }       # preâmbulo do usuário
pytest -q "$@"                          # corpo da tarefa
```

A forma `sh -c 'código' nome arg1 arg2` define `$0=nome` e `$1=arg1` nativamente,
conforme POSIX. Consequências, todas verificadas:

- **stdin permanece livre** — `spur psql`, `spur shell` e `docker run -it` funcionam.
  Um pipe (`echo "$body" | sh -s`) sequestraria o stdin e quebraria toda tarefa
  interativa.
- **Sem arquivo temporário** — nada de `mktemp` (que não é POSIX), nem `trap` de
  limpeza, nem resíduo em Ctrl-C, nem modo de falha em `/tmp` cheio ou somente-leitura.
- **Isolamento** — `exit 1` na tarefa não mata o runner; `set -e` na tarefa não
  contamina o runner.
- **`$0` vira etiqueta de erro** — o shell reporta `spur build: line 3: ...`.

### Opções de shell

`set -e` ligado, `set -u` desligado, `pipefail` inexistente em POSIX.

`set -e` restaura o que o make dava de graça: com um shell por linha, um comando
falho abortava a receita; com o bloco inteiro num shell, precisamos reativar.

`set -u` é opinativo demais para impor — transformaria `$1` ausente em erro cru, em
vez de deixar a tarefa escrever `${1:?informe o ambiente}`. Quem quiser, põe no
preâmbulo.

### Códigos de saída

A tarefa propaga o próprio código **intacto** — CI depende disso. Erros do runner
usam a faixa 64+ (convenção `sysexits`), para nunca colidir com o código de uma tarefa.

| Código | Significado |
|---|---|
| *(o da tarefa)* | Propagado sem alteração |
| 64 | Uso incorreto (flag inválida, tarefa não informada) |
| 65 | Spurfile malformado |
| 66 | Spurfile não encontrado |
| 67 | Tarefa desconhecida |
| 68 | Recursão detectada |

### Ambiente exportado

| Variável | Conteúdo |
|---|---|
| `SPUR_BIN` | Caminho absoluto do runner; é o que faz a função `spur` injetada funcionar fora do PATH |
| `SPUR_ROOT` | Raiz do Spurfile (= cwd da tarefa) |
| `SPUR_INVOCATION_DIR` | Pasta de onde o usuário chamou |
| `SPUR_TASK` | Nome da tarefa em execução |
| `SPUR_STACK` | Pilha de chamadas, para a guarda de recursão |

### Diretório de trabalho

Toda tarefa roda no **diretório que contém o Spurfile em uso**, independentemente de
onde foi invocada. `SPUR_INVOCATION_DIR` preserva a pasta original para quem precisar dela.

Sem isso, `spur test` daria resultados diferentes conforme a pasta de onde foi
chamado, e a busca ascendente viraria armadilha em vez de conveniência.

A regra vale para todas as formas de localizar o arquivo, e `-C` é aplicado antes de tudo:

| Invocação | `SPUR_ROOT` (= cwd da tarefa) |
|---|---|
| `spur test` (busca ascendente) | Diretório onde o Spurfile foi encontrado |
| `spur -f ../outro/Spurfile test` | `../outro/` — a pasta do arquivo apontado |
| `spur -C api test` | `api/`, ou o ancestral de `api/` onde o Spurfile for encontrado |
| `spur -C api -f custom.spur test` | `api/`, onde `custom.spur` é resolvido |

### Guarda de recursão

Tarefas chamam tarefas por subprocesso (`spur deps` dentro de um corpo), então a
detecção de ciclo precisa atravessar processos. `SPUR_STACK` é exportada e acumula
a cadeia; ao entrar numa tarefa, o runner testa se o nome já está na pilha:

```sh
case " ${SPUR_STACK:-} " in
  *" $task "*) die 68 "recursão detectada: ${SPUR_STACK# } -> $task" ;;
esac
```

Detecta apenas **ancestrais**. Uma tarefa chamada duas vezes em sequência (não
aninhada) é permitida, que é o comportamento correto.

## 4. A CLI

```
spur [flags do runner] <tarefa> [argumentos da tarefa...]
```

### Regra de corte das flags

**A primeira palavra que não começa com `-` é o nome da tarefa. Tudo depois dela
pertence à tarefa, intocado.**

```sh
spur -n test          # -n é do runner (dry run de 'test')
spur test -n          # -n é da tarefa, chega como "$1"
spur -C api test -k x # -C api do runner; -k x da tarefa
```

Sem essa regra, cada flag nova que o Spur ganhasse roubaria um nome do espaço de
flags das tarefas. Como o runner nunca olha nada depois do nome da tarefa, o conjunto
de flags pode crescer sem quebrar Spurfile nenhum.

### Flags

| Flag | Efeito |
|---|---|
| `-f ARQUIVO` | Usa outro Spurfile (desliga a busca ascendente) |
| `-C DIR` | `cd DIR` antes de tudo |
| `-l`, `--list` | Lista as tarefas e sai |
| `-n` | Imprime o script montado em vez de executar |
| `-x` | Liga `set -x` após o preâmbulo, com `PS4='$ '` |
| `-h`, `--help` | Ajuda |
| `-V`, `--version` | Versão |

`PS4` é fixado em `'$ '` para que o eco saia como `$ docker build -t app .`, em vez do
`+ ` padrão do shell. A linha `set -x` é inserida **depois** do preâmbulo, de modo que
atribuições de variável e definições de função não poluam a saída.

**Precedência:** `-n` vence `-x`. Com ambas as flags, o script é impresso (já contendo
a linha `set -x`) e nada é executado.

Sem agrupamento de flags curtas (`-xn`): o parsing é um `while`/`case` de vinte
linhas e o ganho não paga a complexidade.

### Descoberta do Spurfile

Procura `Spurfile`, depois `spurfile`, no diretório atual; não achando, sobe um nível
e repete, até `/`.

As duas grafias existem porque macOS e Windows têm sistemas de arquivo
*case-insensitive*, onde `Spurfile` e `spurfile` são o mesmo arquivo, enquanto Linux
distingue. A busca subindo até `/` pode, num diretório sem projeto, alcançar um
Spurfile no `$HOME` — é o mesmo risco que `git` e `just` aceitam, e o `--list` e as
mensagens de erro sempre mostram o caminho resolvido, o que torna a surpresa
diagnosticável.

### Saída do `--list`

```
$ spur --list
Spurfile: /home/dan/projeto/Spurfile

  build      constrói a imagem
  test       roda os testes
  db-reset   recria o banco (destrutivo)
  deploy
```

Tarefas na **ordem do arquivo**, não alfabética: a ordem em que foram escritas carrega
intenção (fluxo principal primeiro, utilitários depois).

`spur` sem argumento nenhum faz exatamente isto — divergência deliberada do make,
que rodaria o primeiro alvo.

## 5. Arquitetura, testes e distribuição

### Arquivo único

O `spur` é **um** script, com o `awk` embutido como string. A alternativa —
`spur` + `resolve.awk` lado a lado — obrigaria o runner a descobrir onde seu próprio
`.awk` mora, atravessando symlinks, `$0` relativo e instalação em `/usr/local/bin`.

Estimativa: 200-300 linhas, organizadas em funções (`parse_args`, `find_spurfile`,
`extract_task`, `list_tasks`, `run_task`, `die`). Sem build step: o arquivo no
repositório é o arquivo que se instala.

```
spur/
├── spur            # o runner
├── Spurfile        # dogfooding: o projeto se usa
├── tests/
│   ├── run.sh      # harness
│   └── cases/
├── docs/superpowers/
└── README.md
```

O repositório local hoje se chama `task-runner`, nome provisório de antes da escolha
da marca. Renomeá-lo para `spur` (e publicá-lo como `esliph/spur`) é parte do plano
de implementação.

O `Spurfile` na raiz não é enfeite: se `spur lint` e `spur test` do próprio projeto
forem desconfortáveis de escrever, o design está errado e isso aparece na primeira semana.

### Testes

**Testes de comportamento.** Harness em sh puro: cada caso monta um Spurfile
temporário, invoca o `spur` e compara stdout, stderr e exit code. Escolhido em vez de
`bats` (exige bash) ou `shellspec` (uma dependência a instalar) porque a ferramenta se
vende como zero-dependência, e exigir um framework para rodar os testes contradiria
isso na primeira linha do CONTRIBUTING. Custo aceito: sem diffs bonitos e sem
`--filter` de fábrica. Estimativa do harness: ~60 linhas.

**Matriz de shells.** É o que transforma "POSIX estrito" de promessa em fato verificado:

| Shell | Papel |
|---|---|
| `dash` | O mais restrito. Se passa aqui, é POSIX de verdade |
| `bash` | O que a maioria usa no dia a dia |
| `busybox ash` | Alpine e containers mínimos, via Docker no CI |
| Git Bash | O ambiente de desenvolvimento do autor |

`dash` e `bash` já estão disponíveis no ambiente de desenvolvimento, o que permite
rodar a checagem de portabilidade localmente, e não apenas no CI.

**`shellcheck -s sh`** no CI, como terceira camada: pega bashismo estaticamente, antes
de virar bug de runtime num Alpine em produção.

### Windows

**O `spur` exige um shell POSIX. No Windows isso significa Git Bash, MSYS2, WSL ou
Cygwin. Não haverá versão nativa para cmd ou PowerShell.**

Esse é exatamente o requisito do `make`, então não é regressão — mas o README precisa
ser preciso sobre o que promete. "Portabilidade" aqui significa *roda em qualquer
Unix, sob qualquer shell POSIX, sem instalar runtime nenhum*. Não significa *roda
nativamente em todo lugar*. `just` e Task, compilados, cobrem Windows nativo melhor;
o Spur ganha onde eles perdem — dentro de um container Alpine, numa máquina sem
toolchain, num servidor onde não se pode instalar binários.

### Instalação

```sh
curl -fsSL https://raw.githubusercontent.com/esliph/spur/main/spur \
  -o ~/.local/bin/spur && chmod +x ~/.local/bin/spur
```

E o modo *vendored*: copiar o `spur` para dentro do repositório e commitá-lo. Quem
clonar roda `./spur test` sem instalar nada, e a função `spur` injetada faz as
chamadas encadeadas funcionarem nesse modo também. Empacotamento (brew, apt) fica
fora do v1.

## Limitações conhecidas

Registradas aqui deliberadamente, como consequências assumidas do design:

1. **Tarefas podem executar mais de uma vez.** Sem grafo, não há dedup: se `build`
   chama `deps` e `lint` também chama `deps`, `deps` roda duas vezes. É o preço da
   chamada explícita, e o ganho é que o passthrough de argumentos permanece simétrico
   e visível no corpo da tarefa.

2. **`-n` não expande a cadeia de chamadas.** Mostra o script montado da tarefa pedida
   e apenas dela. `spur deps` dentro do corpo só acontece em tempo de execução, e
   descobrir isso estaticamente exigiria interpretar o shell. O `make -n` faz melhor,
   porque conhece o grafo antes de rodar. Decidido não incluir heurística (grep por
   linhas que começam com `spur `): um dry-run que acerta 80% das vezes é pior que um
   que declara seu escopo com honestidade.

3. **O `@` por linha do make não é implementável.** O make consegue porque dispara uma
   linha por vez; o Spur entrega o bloco inteiro a um `sh` e não sabe onde cada comando
   começa e termina — há `if`, `for`, pipes e continuação de linha. Implementar isso
   exigiria parsear shell dentro de awk. Os substitutos são `spur -x` (invocação
   inteira) e `{ set +x; } 2>/dev/null` … `set -x` (trecho do bloco). O redirecionamento
   é necessário porque um `set +x` cru ecoa a si mesmo antes de desligar.

4. **O preâmbulo roda a cada tarefa.** Irrelevante se for barato (atribuições, `.env`,
   funções); custoso se alguém puser trabalho pesado ali. Vale documentar no README.

5. **Sem Windows nativo.** Ver a seção Windows.

## Fora do escopo do v1

- Tarefas privadas por prefixo `_` (omitidas do `--list`). Sem pré-requisitos, quase
  todo helper natural vira função no preâmbulo; o caso que sobra é o helper que precisa
  rodar em subprocesso isolado. Adicionar se a dor aparecer.
- Empacotamento em brew, apt ou similares.
- Agrupamento de flags curtas (`-xn`).
- Execução paralela, timestamps, regras de padrão — fora do escopo do produto, não
  apenas do v1.

## Validações já realizadas

As seguintes primitivas foram testadas durante o design, em Git Bash com `dash` e
`bash` disponíveis:

- `sh -c 'código' nome arg1 arg2` define `$0` e os posicionais conforme POSIX.
- `PS4` customizado com `set -x` ativado após o preâmbulo produz eco legível, com
  valores **já expandidos** (`echo 'building myapp:latest'`, não `$IMAGE`).
- `set +x` cru ecoa a si mesmo; `{ set +x; } 2>/dev/null` resolve.
- `set -e` dentro de `sh -c` aborta e propaga o código corretamente.
- stdin permanece livre sob `sh -c`, permitindo tarefas interativas.
- A guarda de recursão via variável de ambiente atravessa processos e detecta
  `a -> b -> a`, retornando código próprio.
- A função `spur` injetada faz chamadas encadeadas funcionarem com o runner chamado
  por caminho relativo, de outro diretório, fora do PATH.
- Argumentos são repassados corretamente em chamadas encadeadas
  (`spur lint --fix` dentro de um corpo).

## Próximo passo

Plano de implementação via skill `superpowers:writing-plans`, com TDD.
