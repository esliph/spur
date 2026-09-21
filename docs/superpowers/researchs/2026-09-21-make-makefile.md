# O que é e para que serve o `make` e o `Makefile`

## TL;DR
- **`make` é uma ferramenta de automação de builds** que, lendo um arquivo de texto chamado `Makefile`, decide o que precisa ser (re)construído comparando as datas de modificação dos arquivos e executa os comandos necessários — foi criada por Stuart Feldman no Bell Labs, tendo surgido em abril de 1976, e continua onipresente em Unix, Linux e macOS.
- **O `Makefile` descreve regras** no formato `alvo: pré-requisitos` seguidas de uma *receita* (comandos indentados obrigatoriamente com TAB); com variáveis, variáveis automáticas (`$@`, `$<`, `$^`), regras de padrão (`%.o: %.c`) e alvos `.PHONY`, ele expressa o grafo de dependências de um projeto.
- **Serve para muito além de compilar C/C++**: é amplamente usado como *task runner* (rodar testes, lint, deploy, gerar docs, orquestrar Docker) em projetos Python/Go/JS; para projetos grandes existem geradores de nível mais alto (Autotools, CMake) e alternativas modernas (Ninja, Meson, `just`, Task).

## Key Findings

- **Origem.** O `make` foi criado por Stuart Feldman no Bell Labs, tendo aparecido pela primeira vez em abril de 1976. A motivação clássica: um colega (Steve Johnson, autor do yacc) desperdiçou uma manhã depurando um programa correto cujo bug já estava consertado — mas o arquivo não fora recompilado, e `cc *.o` não percebeu. Feldman recebeu o ACM Software System Award de 2003; a citação oficial do ACM diz: *"For MAKE — there is probably no large software system in the world today that has not been processed by a version or offspring of MAKE."*
- **Variantes.** As implementações principais são GNU make (a mais comum em Linux, desenvolvida por Richard Stallman e Roland McGrath a partir do fim dos anos 1980 como parte do Projeto GNU, mantida desde a versão 3.76 por Paul D. Smith), BSD make (`bmake`/`pmake`, padrão nos BSDs), o `nmake` da Microsoft (incluído no Visual Studio) e o make especificado pelo POSIX. O alvo especial `.POSIX` permite pedir comportamento padronizado.
- **Como decide o que reconstruir.** Um alvo está "desatualizado" se não existe ou se é mais antigo que qualquer um de seus pré-requisitos (comparação de datas de última modificação). Isso viabiliza *builds incrementais*: apenas o que mudou é refeito.
- **Execução paralela.** A opção `-j`/`--jobs` executa várias receitas simultaneamente, respeitando o grafo de dependências; `-l` limita pela carga do sistema. Muitos Makefiles falham em paralelo por dependências mal declaradas.
- **Armadilhas.** A exigência de TAB no início de cada linha de receita é a pegadinha mais famosa; cada linha da receita roda num *shell separado* (então `cd` não persiste entre linhas); a sintaxe é críptica; e há incompatibilidades entre GNU e BSD make.
- **Ecossistema atual.** Para C/C++, hoje predomina o CMake, que *gera* Makefiles (ou arquivos Ninja); Ninja é um backend rápido; Meson é um gerador moderno; `just` e Task são *task runners* que corrigem as idiossincrasias do make.

## Details

### O que é o `make`

O `make` é uma ferramenta de linha de comando de automação de build: ela lê um arquivo de configuração (o `Makefile`) que descreve *o que* construir, *do que* cada coisa depende e *como* construí-la, e então decide automaticamente quais partes de um programa grande precisam ser recompiladas, emitindo os comandos para fazê-lo. A grande sacada é que o `make` não é limitado a programas — segundo o próprio manual do GNU make, você pode usá-lo para descrever qualquer tarefa em que alguns arquivos precisam ser atualizados automaticamente a partir de outros sempre que estes mudam.

**História.** O `make` nasceu de uma frustração concreta. Como Feldman relatou (citado em *The Art of Unix Programming*), o `make` surgiu de uma visita de Steve Johnson, *"storming into my office, cursing the Fates that had caused him to waste a morning debugging a correct program (bug had been fixed, file hadn't been compiled, `cc *.o` was therefore unaffected)"* — ou seja, entrando furioso no escritório de Feldman após perder uma manhã depurando um programa que já estava correto, só porque o arquivo não fora recompilado. O `make` apareceu pela primeira vez em abril de 1976 no Bell Labs, e se espalhou por vir incluído no Unix (a partir do PWB/UNIX). Feldman ganhou o ACM Software System Award de 2003 por essa contribuição.

**Variantes principais:**
- **GNU make** — a implementação mais rica em recursos e a mais comum em Linux; desenvolvida por Richard Stallman e Roland McGrath a partir do fim dos anos 1980 como parte do Projeto GNU, com manutenção desde a versão 3.76 por Paul D. Smith. Conforme à seção 6.2 do padrão IEEE 1003.2 (POSIX.2).
- **BSD make** (`bmake`/`pmake`) — padrão nos sistemas BSD; conhece só dependências, alvos, regras e macros, delegando parâmetros de sistema em vez de embutir regras. É o make usado para construir os Ports do FreeBSD (`bsd.port.mk`).
- **nmake da Microsoft** — o "Program Maintenance Utility" incluído no Visual Studio; sintaxe parecida mas incompatível com o make Unix, precisa rodar num Developer Command Prompt e expande macros em tempo de parse.
- **POSIX make** — a especificação padronizada (Open Group / IEEE); é, em grande parte, um subconjunto das sintaxes aceitas por quase todas as versões. O alvo especial `.POSIX` habilita o modo padronizado.

### Estrutura de um `Makefile`

A unidade básica é a **regra**:

```makefile
alvo: pré-requisitos
	receita
```

- **Alvo (target)** — normalmente o nome de um arquivo a ser gerado (um executável, um `.o`), mas também pode ser o nome de uma ação (como `clean`).
- **Pré-requisitos (prerequisites/dependências)** — arquivos usados como entrada para criar o alvo. Se qualquer pré-requisito for mais novo que o alvo, o alvo é considerado desatualizado.
- **Receita (recipe)** — uma ou mais linhas de comandos que o `make` executa. **Cada linha da receita precisa começar com um caractere TAB** (ou o caractere definido em `.RECIPEPREFIX`). O manual do GNU make é explícito e literal sobre isso: *"you need to put a tab character at the beginning of every recipe line! This is an obscurity that catches the unwary."*

O **alvo padrão (default goal)** é o primeiro alvo da primeira regra do primeiro Makefile; por isso é comum haver um alvo `all` no topo.

**Variáveis.** Reduzem repetição:

```makefile
CC = gcc
CFLAGS = -Wall -O2
```

Referenciam-se com `$(CC)` ou `${CC}`. Para passar um `$` literal ao shell, escreve-se `$$`.

**Variáveis automáticas** (definidas pelo `make` por regra):
- `$@` — o nome do alvo;
- `$<` — o primeiro pré-requisito;
- `$^` — a lista de todos os pré-requisitos (separados por espaço);
- `$?` — os pré-requisitos mais novos que o alvo;
- `$*` — o "stem" (a parte que casou com `%` numa regra de padrão).

**Regras de padrão (pattern rules).** Uma regra de padrão contém um `%` no alvo: `%.o : %.c` diz como fazer qualquer `arquivo.o` a partir do `arquivo.c` correspondente. Essa é a forma moderna das antigas regras de sufixo.

**Regras implícitas e variáveis embutidas.** O `make` já traz regras implícitas para tarefas comuns. Por exemplo, a receita embutida para compilar um `.c` é essencialmente `$(CC) -c $(CFLAGS) $(CPPFLAGS)` — por padrão `CC = cc`. Redefinindo `CC` ou `CFLAGS` você muda o comportamento sem reescrever a regra. Rode `make -p` num diretório sem Makefile para ver todas as regras e variáveis predefinidas.

**Alvos `.PHONY`.** Um alvo *phony* não corresponde a um arquivo real — é só um nome para uma receita. Declarar `.PHONY: clean` garante que `make clean` sempre rode a receita mesmo que exista um arquivo chamado `clean`, e ainda melhora a performance porque o `make` pula a busca por regras implícitas. Alvos típicos phony: `all`, `clean`, `install`, `test`, `lint`.

### Como o `make` decide o que reconstruir

O critério é simples e baseado em timestamps: **um alvo está desatualizado se não existe ou se é mais antigo que qualquer um de seus pré-requisitos** (comparação das datas de última modificação). A ideia é que o conteúdo do alvo é computado a partir dos pré-requisitos; se um pré-requisito muda, o alvo existente deixa de ser válido e precisa ser refeito. Como o `make` monta um **grafo de dependências**, ele refaz apenas o que foi afetado por uma mudança — isso é o *build incremental*, e é o que torna o `make` muito mais rápido que recompilar tudo.

**Execução paralela (`-j`).** Normalmente o `make` executa um comando por vez. Com `-j`/`--jobs`, ele roda várias receitas simultaneamente, usando o grafo de dependências para respeitar a ordem correta. `make -j` sem número tenta rodar tudo de uma vez (geralmente não é o ideal); `make -j8` limita a 8 jobs. A opção `-l`/`--max-load` limita novos jobs pela carga média do sistema. A grande ressalva: o paralelismo só funciona se as dependências estiverem corretamente declaradas — muitos Makefiles foram escritos assumindo execução serial e quebram (ou, pior, produzem binários incorretos) sob `-j`.

### Para que o `make` é usado

1. **Compilar projetos C/C++** — o caso de uso original e ainda o mais forte, graças a regras de padrão e ao rastreio automático de dependências.
2. **Task runner (executor de tarefas)** — talvez o uso mais comum hoje fora de C. Como `make <alvo>` roda uma sequência de comandos com um nome curto, projetos em Python, Go, JavaScript e outros usam Makefiles para padronizar `make test`, `make lint`, `make build`, `make deploy`, `make docs`, `make docker-build`, etc. Serve como uma "interface" única e autodocumentada para os comandos do projeto.
3. **Orquestração de containers e pipelines** — envolver `docker build`, `docker compose`, migrações de banco e passos de CI/CD.
4. **Fluxos de dados/ciência** — rodar scripts de análise, gerar figuras e relatórios (LaTeX, R) só quando os dados de entrada mudam.

### Exemplo comentado: pequeno projeto em C

```makefile
# Variáveis: compilador e flags
CC = gcc
CFLAGS = -Wall -Wextra -O2

# Lista de objetos
OBJ = main.o util.o

# Alvo padrão (primeiro da lista): o executável final
all: programa

# Linkagem: 'programa' depende dos .o; $@ = programa, $^ = todos os .o
programa: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^

# Regra de padrão: como fazer qualquer %.o a partir do %.c correspondente
# $< = primeiro pré-requisito (o .c); $@ = o alvo (o .o)
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Alvo utilitário sem arquivo real: apaga os artefatos
clean:
	rm -f $(OBJ) programa

# Declara alvos que não são arquivos
.PHONY: all clean
```

Rodando: `make` compila só o que mudou; se você editar `util.c`, apenas `util.o` é recompilado e o programa religado. `make clean` remove os artefatos.

### Exemplo comentado: uso como *task runner* (projeto Python)

```makefile
.PHONY: install test lint format docker

install:          ## instala dependências
	pip install -r requirements.txt

test:             ## roda a suíte de testes
	pytest -q

lint:             ## checa estilo
	ruff check src tests

format:           ## formata o código
	black src tests

docker:           ## constrói a imagem
	docker build -t meuapp:latest .
```

Aqui nenhum alvo corresponde a um arquivo — todos são `.PHONY` — e o `make` é usado puramente para dar nomes curtos e memoráveis a comandos frequentes.

### Comandos de uso comuns

- `make` — constrói o alvo padrão (o primeiro do Makefile).
- `make <alvo>` — constrói/roda um alvo específico (ex.: `make test`).
- `make clean` — por convenção, remove os artefatos de build.
- `make install` — por convenção, instala o programa; em pacotes GNU respeita variáveis como `prefix` (`make install prefix=/usr`) e `DESTDIR` (`make install DESTDIR=/tmp/stage`) para instalações em local alternativo ou *staged installs*.
- `make -j8` — build paralelo com 8 jobs.
- `make -n` — mostra os comandos sem executá-los (dry run).
- `make -f arquivo` — usa um Makefile com outro nome.
- `make -p` — imprime a base de dados de regras e variáveis embutidas.

### Ferramentas relacionadas e alternativas

- **GNU Autotools (`autoconf`/`automake`)** — camada de nível mais alto para portabilidade. O desenvolvedor escreve `configure.ac` e `Makefile.am`; `autoconf` gera o script `configure` e `automake` gera `Makefile.in`. Ao rodar, `./configure` detecta o sistema e gera o `Makefile` final. Daí vem o famoso trio `./configure && make && make install`.
- **CMake** — hoje o *meta build system* dominante para C/C++. Lê `CMakeLists.txt` e **gera** Makefiles, arquivos Ninja, projetos do Visual Studio, etc. É a razão de muitos "Makefiles" existentes serem, na verdade, gerados.
- **Ninja** — backend de build focado em velocidade; seus arquivos `build.ninja` não são feitos para escrita manual — geradores como CMake, Meson e gn os produzem. Trocar o backend do CMake de Make para Ninja costuma acelerar builds.
- **Meson** — gerador moderno, escrito em Python, que usa Ninja como backend padrão; foca em simplicidade e só faz builds *out-of-source*.
- **Task runners modernos** — `just` (escrito em Rust por Casey Rodarmor; usa `justfile`, sintaxe inspirada no make mas sem a exigência de TAB e sem regras implícitas) e Task (escrito em Go; usa `Taskfile.yml` em YAML). Ambos se assumem apenas como executores de comandos, não como sistemas de build com grafo de dependências baseado em timestamps.

### Adoção atual

No ecossistema C/C++, o CMake é hoje amplamente dominante. Na *Annual C++ Developer Survey "Lite" 2023* da ISO C++ Foundation (pergunta "What build tools do you use?", 1.705 respostas, marque todas que se aplicam), os números foram: **CMake 79,88% (1.362), Ninja 42,93% (732), MSBuild 38,53% (657) e Make/nmake 36,89% (629)**. A pesquisa State of Developer Ecosystem 2019 da JetBrains já registrava a virada do CMake: *"Last year CMake beat Visual Studio project to become the most popular project model / build system used for C++ development. Its share has since added 5 percentage points and reached 42%."* O Ninja, por sua vez, vem crescendo: na edição de 2023 da JetBrains, Bryce Adelstein Lelbach (Principal Architect da NVIDIA) comentou *"It is very interesting to see CMake drop in market share and Ninja increase... given CMake's rapid growth until now, this data suggests that it has reached peak saturation."* Ainda assim, o make continua praticamente universal (presente em qualquer Unix/Linux/macOS) e insubstituível como *task runner* leve e sem dependências.

## Recommendations

- **Para automatizar comandos de um projeto (test/lint/build/deploy), use o `make` como task runner.** É universal, já está instalado e um Makefile de 20 linhas com alvos `.PHONY` documenta e padroniza o projeto. Comece por aí.
  - *Mude de abordagem se*: a legibilidade virar problema para a equipe, você precisar de argumentos nomeados, suporte multiplataforma nativo (Windows) ou documentação embutida — nesse caso migre para **`just`** (mais próximo do make) ou **Task** (YAML). Dica: dá para migrar gradualmente, fazendo o `Taskfile` chamar `make` internamente.
- **Para compilar um projeto C/C++ pequeno/pessoal, escreva um Makefile à mão** com regras de padrão (`%.o: %.c`) e variáveis (`CC`, `CFLAGS`). É didático e suficiente.
  - *Mude para CMake quando*: o projeto precisar ser portável entre compiladores/plataformas, tiver muitas dependências, ou você quiser gerar projetos de IDE. O CMake gera os Makefiles/Ninja para você; use o backend Ninja para builds mais rápidos.
- **Sempre declare `.PHONY`** para alvos que não são arquivos (`all`, `clean`, `test`, `install`) — evita bugs se um arquivo homônimo existir e melhora a performance.
- **Ative builds paralelos com `-j`** (ex.: `make -j$(nproc)`), mas só depois de garantir que as dependências estão corretamente declaradas; considere testar com ferramentas de detecção de condições de corrida se o build falhar de forma intermitente.
- **Para portabilidade**, evite extensões específicas do GNU make se o Makefile precisar rodar em BSD; coloque `.POSIX` como primeira linha ou deixe o CMake/Autotools gerarem Makefiles compatíveis.

## Caveats

- **TAB vs. espaços:** a causa nº 1 de erros de iniciante. Cada linha de receita precisa começar com um TAB literal, não espaços (a menos que você mude `.RECIPEPREFIX`). Editores que convertem TAB em espaços quebram o Makefile.
- **Cada linha roda em um shell separado:** comandos como `cd` ou variáveis de shell não persistem para a próxima linha. Soluções: juntar comandos com `&&` e continuação de linha (`\`), ou usar o alvo especial `.ONESHELL`, que passa toda a receita para um único shell. O anúncio oficial de lançamento do GNU make 3.82 (julho de 2010) descreve o recurso: *"New special target: .ONESHELL instructs make to invoke a single instance of the shell and provide it with the entire recipe, regardless of how many lines it contains."*
- **Sintaxe críptica e macros, não variáveis:** as "variáveis" do make tradicional são macros com avaliação recursiva, o que pode surpreender e, em projetos grandes, degradar performance. O GNU make oferece atribuição imediata (`:=`) para mitigar isso.
- **Portabilidade GNU × BSD:** Makefiles simples costumam funcionar nos dois, mas recursos avançados (condicionais, funções, `VPATH`, includes múltiplos) divergem; por isso muitos projetos em Linux exigem `gmake` e projetos BSD usam `bmake`.
- **`make` no Windows não é nativo:** requer WSL, Cygwin, MSYS2 ou o `nmake` (que tem sintaxe própria e incompatível). Task runners modernos como `just`/Task têm melhor suporte multiplataforma.
- **Números de adoção:** as pesquisas citadas (ISO C++ Foundation e JetBrains) são autorrelatadas e têm vieses de amostragem — a JetBrains, por exemplo, tende a pender para usuários de suas próprias ferramentas, e as duas pesquisas usam formulações de pergunta diferentes. Use-as como indicação de tendência, não como medida exata.