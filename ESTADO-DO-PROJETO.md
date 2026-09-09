# DANF — Controle de Repasses (Canaverde & Aguiar Advogados)
**Documento de estado do projeto.** Atualizado em 30/08/2026.
**Leia este arquivo inteiro antes de responder qualquer pedido sobre este sistema.**

---

## 0. Instruções para o assistente (Claude Code)

- **Responder sempre em português (pt-BR).** O usuário é o **Danilo Ferro**, da área **Financeira e Administrativa** — ele gerencia uma equipe no escritório, mas **não é advogado**. É **leigo em programação**. Explicar sem jargão, passo a passo, dizendo o **porquê** junto do **como**.
- **Nunca editar `atendimento.html` na mão.** Editar **sempre** `index.html` e rodar `python3 transform.py` para regerar o gêmeo.
- **Validar antes de entregar:** extrair o último `<script>` e rodar `node --check`.
- **Banco em produção com dados reais.** Toda migração deve ser **aditiva** (`add column if not exists`, `create or replace`). **Nunca** recriar tabela nem re-inserir dados.
- **Testar mudanças de banco dentro de transação com `rollback`** antes de aplicar de verdade (ver §9).
- Ao terminar um assunto, **oferecer o resumo atualizado deste documento**.

---

## 1. O que é

Sistema web para controlar repasses de valores a clientes do escritório. Chama-se **DANF**; o subtítulo é **Controle de Repasses** e uma etiqueta ao lado do nome mostra em qual sistema a pessoa está (**GESTÃO** ou **ATENDIMENTO**). Dois aplicativos HTML de página única (vanilla JS, sem framework, sem build), ligados a um banco Supabase compartilhado, publicados na Vercel via GitHub.

- **`index.html`** — acesso da **gestão**. Vê valores, tempo pendente, financeiro, gerencia usuários.
- **`atendimento.html`** — acesso do **atendimento**. **Nunca vê valores** e **não altera pagamento** (bloqueio no banco, não só na tela).

Os dois leem/gravam a mesma base: o que um faz, o outro vê (atualização automática a cada 30s + botão Atualizar).

---

## 2. Endereços e acessos

- **Repositório:** https://github.com/ropelimi/repasses (branch `main`)
  *(o endereço antigo `danilo-ferro/sistema-repasses-canaverde` estava neste documento até 23/07/2026 e não é mais o repositório usado.)*
- **Supabase project_id:** `maytgfyzvoufepaerwwn`
- **SUPABASE_URL:** `https://maytgfyzvoufepaerwwn.supabase.co`
- **Chave publicável:** `sb_publishable_U4pGdy1Bom36dZ2bo6nb3g_VMAAYELY` (pública por design; já está dentro dos HTML). A chave **secret/service_role NUNCA** vai para o site nem para o repositório.
- **Vercel:** conectado ao GitHub → commit no repo republica sozinho (~30s), URL fixa.

**Estado da publicação em 10/08/2026:** GitHub, Vercel e os arquivos locais estão **100% em sincronia**. O conteúdo publicado é exatamente o descrito neste documento.

**Arquivos do repositório:** `index.html`, `atendimento.html`, `favicon.png`, `transform.py`, `ESTADO-DO-PROJETO.md`, `MIGRACOES-APLICADAS.sql`.

**Storage do Supabase:** bucket **privado** `anexos` guarda os comprovantes e documentos. Os arquivos só abrem por link assinado (válido por 2 minutos), gerado depois do login.

---

## 3. Banco de dados (Supabase)

### Tabela `repasses` — **268 lançamentos** (~R$ 647.565,25 | 25 pagos, 2 ag. pagamento, 241 pendentes em 30/08/2026)
`id` (bigint identity), `nome`, `nome_norm` (sem acento, maiúsculo), `cpf`, `processo`, `reu`, `grupo`, `advogado`, `tipo`, `conta`, `competencia` ("Mmm/AAAA"), `ano`, `mes`, `valor_num` (numeric), `busca`, `cp` (bool), `pago` (bool), **`ag_pagamento` (bool)**, **`previsao_pagamento` (date)**, **`natureza` (text: `repasse` | `devedor`)**, **`tipo_devedor` (text)**, **`devedor_quitado` (bool)**, `data_pagamento` (text ISO), `valor_pago` (text BR), `obs`, `pix_chave`, `pix_banco`, `pix_agencia`, `pix_conta`, `atualizado_por`, `atualizado_em`, `criado_em`.

**Os três status saem de duas colunas booleanas** (não existe coluna "status"):

| `pago` | `ag_pagamento` | Status na tela |
|---|---|---|
| `false` | `false` | **PENDENTE** |
| `false` | `true`  | **AG. PAGAMENTO** — separado, com repasse já programado |
| `true`  | `false` | **PAGO** |

`pago` manda: o trigger `trg_normaliza_status` zera `ag_pagamento` sempre que `pago` vira `true`, então a quarta combinação nunca existe no banco.

ADV (rótulo desde 31/08/2026; a coluna no banco continua se chamando `grupo`), **11 opções** desde 04/09/2026:

- **Advogados:** Max, Mariah, Jezieli, Yunes, Kaled, **Isabelle**, **Déborah**, **Gleisy** — cada um responde pelos próprios casos (`advogado` = o próprio nome, `tipo` = `cliente`).
- **Grupos parceiros:** Nardon, JLM, Máximo Êxito — apontam para o Max (`advogado` = `Max`) e têm `tipo` próprio (`nardon`, `jlm`, `maximo_exito`).

A ordem dessa lista (`GORDER`) é a que aparece nos chips de filtro e no formulário: advogados primeiro, grupos parceiros depois. **Não há restrição no banco** — `grupo` é texto livre, então acrescentar um ADV é mudança só de tela, sem migração. Cada ADV tem uma cor de etiqueta própria (`gcls()` → `.g-*`); as novas usam variáveis definidas nos **dois temas** (`--amarelo`, `--lima`, `--magenta`).

> As cores do **Kaled** e do **JLM** ainda são hexadecimais fixas, então no modo escuro elas continuam com fundo claro. Não incomoda a leitura e não foi mexido para não trocar cores que o pessoal já reconhece; se um dia for arrumar, basta criar `--teal` e `--indigo` nos dois temas, como foi feito com as três novas.

### Tabela `profiles`
`id` (uuid → `auth.users`, **ON DELETE CASCADE**), `email` (text), `nome` (text), `perfil` (text NOT NULL, default `'atendimento'`, valores `gestao` | `atendimento`).

- **RLS:** policy `perfil_proprio` — cada usuário só enxerga **o próprio** registro.
  → Por isso a lista de usuários do painel usa a função `listar_usuarios()`, e **não** um `select` direto em `profiles`.
- Trigger `handle_new_user` (em `auth.users`) cria o profile automaticamente com perfil `atendimento` e **sem nome**.

### Segurança de valores (atendimento não vê dinheiro)
- **RLS na `repasses`:** policy `repasses_gestao` — só perfil `gestao` acessa a tabela (que tem valores).
- **View `repasses_atendimento`** (`security_invoker = off`) — é por ela que o atendimento lê e grava. Inclui `ag_pagamento`, `previsao_pagamento`, `natureza` e `tipo_devedor` (são status, não dinheiro).
  - **Nunca expõe `valor_pago`.**
  - **`valor_num` só do saldo devedor** (30/08/2026, a pedido): a coluna sai como `case when natureza = 'devedor' then valor_num else null end`. O atendimento vê quanto o cliente deve — o que ajuda a identificar e conversar com ele — e o repasse continua invisível.
  - Como essa coluna é **calculada**, o Postgres a torna **não atualizável**: o atendimento lê mas não consegue gravar valor nem por chamada direta. As demais colunas continuam graváveis normalmente.
- **Função `recibo_dados(bigint[])`** (security definer) — entrega o valor só dos lançamentos escolhidos, para o atendimento gerar recibo. **Está concedida (`granted`).**
  Para bloquear: `revoke execute on function public.recibo_dados(bigint[]) from authenticated;`

### Segurança de pagamento (3ª versão, 30/08/2026)
- **Trigger `trg_bloqueia_pagamento`** (BEFORE INSERT OR UPDATE em `repasses`) → função `bloqueia_pagamento_nao_gestao()`.
- Impede que **qualquer usuário logado que não seja `gestao`** altere `pago`, `data_pagamento`, `valor_pago`, **`previsao_pagamento`** e **`devedor_quitado`** — pela tela, pela view ou por chamada direta à API.
- **`ag_pagamento` fica FORA da trava, a pedido:** o atendimento **pode** mover um lançamento entre PENDENTE e AG. PAGAMENTO (pela tela de edição). O que ele nunca faz é marcar PAGO nem mexer em valores ou na data prevista.
  > ⚠️ **Regressão já cometida uma vez.** Em 30/08/2026, ao reescrever a função inteira na migração do saldo devedor, a trava de `ag_pagamento` voltou por engano e o atendimento ficou sem conseguir mudar o status. Foi corrigida no mesmo dia. **Ao mexer nesta função, confira sempre se `ag_pagamento` continua fora da lista de bloqueados** — a linha existe só como comentário no código, é fácil perder.
- `auth.uid()` nulo (service_role / migrações) **passa livre**, de propósito.
- A restrição na tela é apenas cosmética; **a trava real é esta**.

### Coerência do status e previsão automática
- **Trigger `trg_normaliza_status`** (BEFORE INSERT OR UPDATE) → função `normaliza_status_repasse()`.
- `pago = true` força `ag_pagamento = false`. Um lançamento pago não fica "aguardando pagamento".
- Virou **AG. PAGAMENTO** sem previsão → agenda o **próximo dia 20 útil** (regra no §3.1). Voltou para **PENDENTE** → a previsão é limpa. Ficou **PAGO** → a previsão é mantida, como histórico.
- `natureza = 'repasse'` limpa `tipo_devedor` e `devedor_quitado` sozinho. Só um lançamento de saldo devedor pode estar "quitado".
- Roda **depois** da trava (ordem alfabética: `trg_bloqueia_pagamento` → `trg_marca_autor` → `trg_normaliza_status`), então a trava sempre enxerga o que o usuário realmente tentou gravar.
- **Testado com `rollback`** antes de aplicar: 12 cenários de status/previsão + 8 de anexos.

### 3.1 Previsão de pagamento — o "dia 20 útil"
Funções (todas `immutable`, sem tabela para manter):

| Função | O que faz |
|---|---|
| `pascoa_br(ano)` | Calcula a Páscoa (algoritmo de Meeus), base dos feriados móveis. |
| `eh_feriado_br(data)` | Nacionais fixos + **25/01** (aniversário de São Paulo) + **09/07** (Revolução Constitucionalista) + Carnaval (segunda e terça), Sexta-feira Santa e Corpus Christi. |
| `dia_util_anterior(data)` | Anda para trás até cair em dia útil. |
| `previsao_dia20(data)` | **Até o dia 15** → dia 20 do próprio mês. **Do dia 16 em diante** → dia 20 do mês seguinte. Se o dia 20 for fim de semana ou feriado, antecipa. |

Conferido: alterado em **05/09/2026** → previsão **18/09/2026**, porque 20/09 cai num domingo.

> ⚠️ **Ponto facultativo e feriado forense não entram** (só os feriados da lista acima). Se precisar de exceções, o caminho é trocar `eh_feriado_br` por uma tabela de feriados — foi a opção descartada em 30/08/2026.

**⚠️ Existe uma cópia dessa regra em JavaScript, e ela precisa continuar igual.** Desde 01/09/2026 a tela calcula a mesma data para **mostrar** ao usuário assim que ele marca AG. PAGAMENTO, antes de salvar (funções `pascoaBR`, `ehFeriadoBR`, `diaUtilAnterior` e `previsaoDia20`, espelhos de `pascoa_br`, `eh_feriado_br`, `dia_util_anterior` e `previsao_dia20`). **Quem grava continua sendo o trigger do banco** — a tela só antecipa o que vai acontecer. Se a regra mudar no banco, mude também no `index.html`, senão a tela promete uma data e o banco grava outra. O teste `teste-prev.js` compara as duas contas dia a dia nos 5 anos entre 2026 e 2030 (1.826 dias e os 75 feriados) por impressão digital `md5` — se divergirem em um único dia, ele acusa.

### Tabela `clientes` (NOVO em 30/08/2026)
`nome_norm` (pk), `nome`, `obs`, `cp` (bool), `atualizado_por`, `atualizado_em`, `criado_em`.

- Guarda a **observação geral** e o **C.P. do cliente inteiro** — vale para todos os processos dele. Não guarda valor nenhum.
- **RLS:** quem está logado lê, cria e atualiza (gestão e atendimento); **só a gestão exclui**.
- Trigger `trg_marca_autor_cliente` carimba quem mexeu e quando.
- A observação **por processo** continua existindo, na coluna `repasses.obs`. São duas coisas diferentes.

### Tabela `anexos` + bucket `anexos` (NOVO em 30/08/2026)
`id`, `repasse_id` (nulo = anexo geral do cliente, `on delete cascade`), `cliente_norm`, `arquivo` (caminho no bucket, único), `nome_arquivo`, `mime`, `tamanho`, `categoria` (`recibo` | `comprovante` | `documento`), `criado_por_email`, `criado_por_nome`, `criado_em`.

- **O atendimento vê e baixa tudo** — anexo não tem valor dentro, então não fere a regra de "atendimento não vê dinheiro". É assim de propósito: era o pedido.
- **RLS da tabela:** todo mundo logado LÊ; ao inserir, `criado_por_email` **tem que ser** o e-mail de quem está logado (não dá para forjar autoria); excluir só a **gestão** ou **quem enviou**.
- **RLS do Storage** (`anexos_obj_leitura` / `_envia` / `_exclui`): as mesmas regras, usando `owner = auth.uid()`.
- Bucket **privado**: o arquivo só abre por **URL assinada de 2 minutos**, gerada pelo navegador depois do login.
- **Testado com `rollback`:** 8 cenários, incluindo atendimento tentando anexar em nome de outra pessoa (recusado) e tentando apagar anexo alheio (recusado).

### Gerenciamento de usuários (NOVO em 23/07/2026) — todas SECURITY DEFINER, só `gestao`
| Função | Argumentos | O que faz |
|---|---|---|
| `listar_usuarios()` | — | Lista `email`, `nome`, `perfil`. Devolve **0 linhas** se quem chama não for gestão. |
| `admin_criar_usuario(p_email, p_nome, p_senha, p_perfil)` | text ×4 | Cria em `auth.users` + `auth.identities` + ajusta `profiles`. |
| `admin_atualizar_usuario(p_email, p_nome, p_perfil, p_nova_senha)` | text ×4 | Atualiza nome/perfil; troca a senha **só se** `p_nova_senha` vier preenchida. |
| `admin_excluir_usuario(p_email)` | text | Apaga identidade + usuário (o profile sai por cascata). |
| `admin_definir_senha(target_email, nova_senha)` | text ×2 | **Legada.** Trocava só a senha. Substituída por `admin_atualizar_usuario`. Mantida por compatibilidade; **não é usada pela tela**. |

**Proteções embutidas (testadas):** perfil não-gestão é recusado; e-mail duplicado barrado; senha mínima 6 caracteres; perfil só aceita `gestao`/`atendimento`; **não** dá para excluir a própria conta; **não** dá para excluir nem rebaixar o **último** usuário `gestao`.

> ⚠️ **Senha:** as funções gravam o hash com `extensions.crypt(senha, gen_salt('bf'))` — mesmo padrão bcrypt do Supabase Auth. Funciona bem neste porte, mas é acoplado ao formato interno do GoTrue; se o Supabase mudar isso, precisará de ajuste.

> ⚠️ **E-mail é a chave de login.** Por isso o painel deixa o e-mail **somente leitura** na edição. Para trocar o e-mail de alguém: excluir e criar de novo.

### Histórico / auditoria
- Tabela `repasses_log` + view `repasses_log_atendimento` (filtra linhas de valor).
- Triggers `trg_marca_autor` (carimba `atualizado_por`/`atualizado_em`) e `trg_registra_log` (grava criou/alterou/excluiu, campo, de → para, quem, quando).
- Funções `meu_perfil()`, `meu_email()`, `meu_nome()`.
- Grava desde 15/07/2026. **Não há histórico anterior a isso.**

### Usuários cadastrados (11 em 23/07/2026)
| Nome | E-mail | Perfil |
|---|---|---|
| Danilo Ferro | canaverdeadvogados8@gmail.com | gestao |
| Fernanda Simões | canaverdeadvogados27@gmail.com | gestao |
| Caio Soares | csoares.canaverdeadvs@gmail.com | gestao |
| Max Canaverde | max.etecfran@gmail.com | gestao |
| Anderson Andrade | canaverdeadvogados2@gmail.com | atendimento |
| Jorge Mesquita | canaverdeadvogados11@gmail.com | atendimento |
| Isabela Guedes | iguedes.canaverdeadvs@gmail.com | atendimento |
| Irís Pereira | ipereira.canaverdeadvs@gmail.com | atendimento |
| Jenifer Gonçalves | jgoncalves.canaverdeadvs@gmail.com | atendimento |
| Lucas Mesquita | lmesquita.canaverdeadvs@gmail.com | atendimento |
| Nathalia Gomes | ngomes.canaverdeadvs@gmail.com | atendimento |

---

## 4. Funcionalidades prontas

1. **Lista de lançamentos** — busca (ignora acentos), filtros por status (Todos / Pendentes / **Ag. pagamento** / Pagos), ano, mês, **intervalo de competência** (§4.10) e ADV, "Só C.P.", ordenação, visão *Por lançamento* e *Por cliente* (consolidada).
2. **Tempo pendente** (só gestão) — calculado pela **competência**: ≤3m verde, 4–6 amarelo, 7–12 laranja, >12 vermelho. Desde 01/09/2026 aparece como pastilha **embaixo da competência**, na mesma coluna, e não mais numa coluna própria (ver §10). Continua com linha própria na ficha de Detalhes / OBS e coluna própria no CSV.
3. **Baixa de pagamento** (**só gestão**) — data e valor pago **já vêm preenchidos**: a data com hoje e o valor com **exatamente o valor lançado**, para não haver erro de digitação. Os dois continuam editáveis, para o caso de pagamento parcial. Ao salvar, marca PAGO e limpa o "ag. pagamento".
4. **Três status: PENDENTE → AG. PAGAMENTO → PAGO** (atualizado em 10/08/2026)
   - Na gestão o status é um **botão que gira em ciclo** a cada clique, nessa ordem, e do PAGO volta para PENDENTE.
   - No atendimento é **texto fixo (somente leitura)** — e a trava real está no banco, não só na tela.
   - **AG. PAGAMENTO** = caso separado, com o repasse ao cliente já programado. Fundo azul-claro na linha, etiqueta azul.
   - **PAGO** = a linha inteira sai com o **texto riscado** (cliente, CPF, processo, réu, competência, valor). Botões, etiquetas de grupo e o "tempo pendente" **não** são riscados, para continuarem legíveis. Funciona no computador, no celular e nos modos claro e escuro.
   - Cartões do topo: para a gestão, **"A repassar (não pago)"** soma tudo que ainda não foi repassado (pendente **+** ag. pagamento) e **"Ag. pagamento"** mostra quanto já está programado. No atendimento os dois cartões mostram quantidade, não valor.
   - **Cuidado com o filtro:** "Pendentes" mostra só o que **ainda não foi separado**; o que está programado aparece em "Ag. pagamento". O cartão de valor, ao contrário, soma os dois — é o total que o escritório ainda deve repassar.
   - O **Financeiro** continua contando **só o que está PAGO** — separar para pagamento não entra no total. Mas desde 30/08/2026 ele **mostra os separados numa seção própria** ("A pagar — separados para pagamento"), com o botão **$** para dar a baixa sem sair da aba e uma **linha de total no rodapé da tabela** (valor lançado, valor a pagar e a conta do saldo devedor). Essa seção **ignora o período** do filtro (que é por data de pagamento) e **ignora a aba de status** — senão, estando em "Pagos", ela apareceria vazia.
   - **Os cartões do topo são clicáveis** (30/08/2026): cada um aplica o filtro daquilo que mostra, e clicar de novo volta para "Todos". O cartão ativo fica com a borda azul.

| Cartão | O que faz ao clicar |
|---|---|
| A repassar (líquido) | filtro `aberto` — tudo que ainda não foi repassado (pendentes + separados) |
| Saldo devedor | filtro `devedor` — só as dívidas do cliente |
| Ag. pagamento | filtro `agp` |
| Lançamentos | limpa o filtro de status |
| Clientes | abre a visão *Por cliente* |
| Pagos | abre o Financeiro (na gestão) |
| C.P. | liga/desliga o "Só C.P." |

   Os filtros **`aberto` e `devedor` existem só pelos cartões** — não têm botão na barra de status, para não deixá-la larga demais no celular. Como nenhum botão da barra fica aceso nesses dois casos, é a **borda azul do cartão** que mostra o que está ativo.
   - **Os cartões do topo ignoram a aba de status** (30/08/2026). Eles resumem o filtro de grupo, período e busca; cada cartão já é de um status. Antes, na aba "Pagos" eles zeravam ("A repassar R$ 0,00") ao lado do Financeiro mostrando R$ 5.300,00 a pagar. Quem diz o que está na lista é o "Exibindo X de Y".
   - **Também dá para trocar o status dentro da edição do lançamento** (§4.11). Na gestão, as três opções; no atendimento, só PENDENTE e AG. PAGAMENTO.
   - Clicar em **"Pagos"** (gestão) **abre direto o Financeiro**, mantendo os filtros que já estavam aplicados. Sair de "Pagos" volta para "Por lançamento".

11. **Status na edição, previsão de pagamento, Detalhes/OBS, anexos e saldo devedor** (NOVO em 30/08/2026) — ver §4.1 a §4.5 abaixo.

### 4.1 Status dentro da edição
Campo **Status** no formulário de edição. Gestão vê PENDENTE / AG. PAGAMENTO / PAGO; atendimento vê só PENDENTE / AG. PAGAMENTO. Se o lançamento **já está PAGO**, o atendimento vê o status como texto fixo e o formulário **não envia** nada de pagamento — se enviasse, o banco recusaria e daria erro na cara do usuário.

### 4.2 Previsão de pagamento
Campo de data no formulário. Preenchido sozinho pelo banco ao virar AG. PAGAMENTO (regra do dia 20 útil, §3.1). **A gestão pode trocar na mão; o atendimento vê o campo desabilitado.** A previsão também aparece na lista (`prev. 18/09/2026`, embaixo do status) e na ficha de detalhes.

Desde 01/09/2026 a data **aparece na hora**, ainda no formulário: ao escolher AG. PAGAMENTO o campo já se preenche e a linha de ajuda diz *"Programado para 18/09/2026 — o próximo dia 20 útil"*, para o usuário saber para quando o repasse ficou programado antes de salvar. Vale para os dois perfis (no atendimento o campo continua travado, só que agora com a data à vista). Voltando para PENDENTE o campo é limpo, que é o que o banco faz. Quem calcula na tela é o `previsaoDia20()` do JavaScript — **um espelho da função do banco, ver o aviso no §3.1**.

### 4.3 Detalhes / OBS (ícone de olho)
Botão **👁 Detalhes / OBS** em **todas as linhas, nos dois perfis** — antes o atendimento tinha um ícone parecido com o de Editar e as pessoas confundiam. Abre uma ficha com todos os dados do lançamento, a observação (editável) e um atalho para os anexos e para o histórico.
Na **visão Por cliente** há o mesmo botão, mas para o **cliente inteiro**: observação geral, marcação **C.P. do cliente**, resumo de valores (repasses em aberto, saldo devedor e líquido), lista dos processos e todos os anexos.
O ícone **$** (financeiro e baixa) continua existindo, **só na gestão**, separado do olho.

### 4.4 Anexos (ícone de clipe)
Botão de **clipe** com o número de arquivos: na linha do lançamento, na visão por cliente, na baixa de pagamento, na tabela do Financeiro e dentro do recibo ("Anexar recibo assinado").
- Envia qualquer arquivo até **20 MB**, classificado como **Comprovante**, **Recibo assinado** ou **Documento**.
- Anexo de um processo aparece **no processo e na ficha do cliente**; anexo geral do cliente aparece **nos dois lugares também**.
- **O atendimento anexa, vê e baixa** — inclusive comprovantes de pagamento, mesmo sem ter acesso ao Financeiro.
- **Excluir:** a gestão apaga qualquer um; as demais pessoas só o que elas mesmas enviaram.

### 4.5 Saldo devedor
No **Novo lançamento**, o primeiro campo é **Tipo de lançamento**: *Repasse ao cliente* ou *Saldo devedor*. Escolhendo Saldo devedor aparece o **tipo**: Custas, Má-Fé, Réu, Indenização, Escritório, Estado.
> Em 01/09/2026 saíram do formulário, a pedido, dois avisos que não acrescentavam nada: *"Saldo devedor abate do valor consolidado do cliente e não entra no Financeiro"* e, no atendimento, *"Saldo em aberto. Somente a gestão altera."*. A caixinha **Saldo quitado** passou a existir só para a gestão — no atendimento o bloco inteiro deixou de ser gerado, e a situação continua visível na lista, pela pastilha EM ABERTO / QUITADO.
- Os dois aparecem **separados** na lista, com etiqueta marrom no saldo devedor.
- **Saldo devedor não tem status nem previsão de pagamento** (mudança de 30/08/2026, a pedido). Ele serve só para abater de repasses e como informação nos casos de cliente sem repasse. Na coluna Status aparece o tipo (Custas, Má-Fé…) no lugar do botão; o botão **$** (baixa) não aparece; e ele fica **fora dos filtros** Pendentes / Ag. pagamento / Pagos, aparecendo só em "Todos".
- **Como um saldo devedor "sai" da conta:** marcando **Saldo quitado** (ver §4.9), editando ou excluindo o lançamento.
- O banco garante isso sozinho: o trigger `trg_normaliza_status` zera `pago`, `ag_pagamento`, `previsao_pagamento`, `data_pagamento` e `valor_pago` de qualquer lançamento com `natureza = 'devedor'`.
- Na **ficha do cliente** o valor sai **abatido**: repasse de R$ 3.000 com custa de R$ 500 mostra **R$ 2.500**, com a conta escrita embaixo.
- **Não entra no Financeiro** (decisão de 30/08/2026: o Financeiro é o dinheiro que saiu para o cliente) e **não entra no recibo de quitação**.
- Nos cartões do topo: **"A repassar (líquido)"** já é repasses − devedores, e um cartão **"Saldo devedor"** aparece quando existe algum em aberto. Na **gestão** esse cartão mostra o **valor**; no **atendimento**, a **quantidade de lançamentos** (mudança de 31/08/2026, a pedido — o atendimento continua vendo o valor de cada saldo devedor na lista, na ficha e no cartão do cliente, só não vê o total somado).

### 4.10 Filtro por intervalo de competência (NOVO em 09/09/2026)
Além dos seletores de **Ano** e **Mês** (que filtram um ano ou um mês por vez), o botão **Intervalo** abre uma barra com *Competência de \[mês/ano\] até \[mês/ano\]*, mais os atalhos **Últimos 12 meses**, **Este ano**, **Ano passado** e **Limpar**.

- O filtro entra dentro do `applyFilters()`, então vale de uma vez para as três visões — *Por lançamento*, *Por cliente* e *Financeiro* — e para os cartões do topo, sem precisar repetir a regra em cada tela.
- A competência é guardada em duas colunas (`ano` e `mes`). A comparação monta a chave `'AAAA-MM'`, que é exatamente o formato que o `<input type="month">` devolve — comparar texto nesse formato já dá a ordem certa, sem montar data. É o `compChave(r)`.
- **Enquanto o intervalo vale, os seletores de Ano e Mês ficam desabilitados** e são ignorados pelo filtro. Os dois mecanismos juntos só confundiriam ("por que sumiu tudo?").
- **Fechar a barra limpa o intervalo**, de propósito: filtro ligado e escondido é a receita de "sumiram lançamentos e ninguém sabe por quê". O botão fica aceso enquanto a barra está aberta e a barra mostra o resumo em português (*"Mostrando Mar/2025 – Set/2025."*), porque o `<input type="month">` é desenhado pelo navegador e aparece no idioma dele.
- Deixar só uma ponta é válido e a barra avisa (*"Sem fim: pega de Out/2026 em diante."*). Escolhendo o fim antes do início, a outra ponta é empurrada junto, em vez de devolver lista vazia sem explicação.
- **Custo de largura:** o botão novo somou 98px à barra de controles e empurrava os botões de visão para uma segunda linha a partir de 1366px. Devolvidos com três cortes cosméticos — `.seg button` de 13 para 11px de padding, `.search` com `min-width` de 210 para 170px e o rótulo "Intervalo…" sem as reticências. **A barra volta a caber numa linha só a partir de 1247px** (era 1366px com o botão largo).

> O **Financeiro** já tinha o seu próprio intervalo (`finDe` / `finAte`), mas sobre a **data de pagamento**. São coisas diferentes e convivem: um filtra por competência, o outro por quando o dinheiro saiu.

### 4.9 Saldo quitado (NOVO em 31/08/2026)
Quando o caso é resolvido, a gestão dá o saldo devedor por **quitado** — ele **para de abater** do cliente, mas **continua no histórico**.

- Coluna `devedor_quitado` (bool, default `false`) em `repasses` e na view `repasses_atendimento`.
- Na coluna **Status** de cada saldo devedor aparece uma pastilha: **EM ABERTO** (cinza) ou **QUITADO** (verde). Na gestão é um botão — um clique alterna, com confirmação ao quitar. No atendimento é só um selo, sem clique.
- Também está no **formulário de edição** (caixinha "Saldo quitado — para de abater do cliente"), que só aparece quando o tipo de lançamento é *Saldo devedor*.
- Quitado, o lançamento fica **riscado** na lista e no cartão do cliente, como um pago.
- **Só a gestão marca.** A trava do banco (`bloqueia_pagamento_nao_gestao`) bloqueia `devedor_quitado` junto com `pago` e `previsao_pagamento`.
- Sai do CSV (coluna Status: `SALDO QUITADO` / `SALDO EM ABERTO`) e do Histórico (campo "Saldo quitado").
- Um saldo quitado **não entra** em `devedorDoCliente()`, nem no abatimento dos repasses, nem nos cartões do topo, nem na contagem "N saldo devedor" do cartão do cliente. Quem ignora o quitado é o helper `devEmAberto(r)` — use ele, não `ehDevedor(r)`, sempre que a pergunta for "quanto o cliente ainda deve".
- O **filtro** "Saldo devedor" (cartão do topo) continua mostrando **todos**, quitados inclusive, para ser possível achar e reabrir um deles. Por isso o cartão pode dizer "1" e a lista trazer 2 linhas — a segunda vem riscada e marcada QUITADO.
- **Testado com `rollback`** antes de aplicar: 6 cenários, incluindo a guarda de regressão do `ag_pagamento`.

### 4.6 Saldo a pagar já com o desconto (NOVO em 30/08/2026)
Quando um repasse está em **AG. PAGAMENTO** e o cliente tem saldo devedor, a tela mostra **quanto sai de fato**:

> R$ 3.750,00
> **a pagar R$ 3.300,00** — R$ 3.750,00 − R$ 450,00 devedor

Aparece na coluna Valor da lista, na visão *Por cliente* e na ficha de Detalhes / OBS. O cartão **"Ag. pagamento"** do topo também já soma o valor líquido.

**O desconto é aplicado uma vez só.** Se o cliente tem vários lançamentos separados, `calcAbatimentos()` distribui o saldo devedor do primeiro para o último (ordenando pela previsão e depois pelo id), até acabar — nunca descontando a mesma dívida duas vezes. A conta usa **todos** os lançamentos, não só os que estão passando pelo filtro da tela; senão filtrar por "Ag. pagamento" esconderia o devedor e o desconto sumiria.

Onde mais o líquido aparece:
- **Cartão do cliente** (visão *Por cliente*) e **ficha do cliente** — com a conta escrita embaixo.
- **Baixa de pagamento** (o botão **$**) — uma tarja azul "A pagar: R$ 3.300,00" e o campo **Valor pago já preenchido com o líquido**, porque é esse o dinheiro que sai. Continua editável para pagamento parcial.
- Marcar PAGO pelo botão de status ou pelo formulário também grava o líquido.

**O desconto vale para qualquer repasse em aberto**, não só os que estão em AG. PAGAMENTO — mas a ordem de aplicação é: primeiro os separados para pagamento, depois os pendentes (por previsão e id).

**A conta do cliente usa TODOS os lançamentos dele, nunca só os filtrados.** Foi um bug real em 30/08/2026: com o filtro "Ag. pagamento" ligado, o saldo devedor saía da lista e o cartão mostrava R$ 3.750,00 em vez de R$ 3.300,00. Vale para `renderCards`, `renderDetCliente` e `calcAbatimentos` — todos passam por `todosDoCliente(nome_norm)`.

Só a gestão vê esses valores (o atendimento não vê dinheiro).

### 4.8 Busca e formato do CPF (30/08/2026)
- A busca acha o CPF e o processo **com ou sem pontos**: digitar `12345678900` encontra `123.456.789-00`, e vice-versa. Antes não achava — a `busca` gravada no banco só tinha a versão pontuada.
- Funciona comparando **duas coisas em paralelo**: o texto (como antes) e, quando há 3 números ou mais, só os dígitos dos dois lados.
- Ao salvar um lançamento, o CPF é **gravado no formato padrão** (`formataDoc`): 11 números viram `123.456.789-00`, 14 viram `12.345.678/0001-99`, e qualquer outra coisa fica como foi digitada (o sistema não inventa). O campo também se ajeita sozinho ao sair dele.
- A coluna `busca` passou a guardar **também os números sem pontuação**, para os lançamentos novos.
- Em 30/08/2026 os **269 CPFs já estavam no formato padrão** — não houve correção de dados a fazer.

### 4.7 Sugestões ao digitar no cadastro (NOVO em 30/08/2026)
Para não cadastrar o mesmo cliente com nomes ou CPFs diferentes — erro de digitação é o problema nº 1 de consistência aqui.

Campos com sugestão: **Nome do cliente**, **CPF**, **Nº do processo** e **Réu**.

| Você digita | O sistema mostra | Clicando, preenche |
|---|---|---|
| 2+ letras do nome | clientes já cadastrados, com CPF e quantos lançamentos | nome **e** CPF |
| 3+ números no CPF | o mesmo, achando pelo CPF | nome **e** CPF |
| 2+ letras do réu | réus já cadastrados | réu |
| 3+ números ou letras do processo | processos já cadastrados, com o cliente | processo, nome, CPF, réu **e** grupo |

- Funciona com **seta para cima/baixo + Enter**, além do clique. **Esc** fecha a lista (e só depois fecha o formulário).
- **Ignora acento e pontuação:** digitar "sara basilio" acha "SARA BASÍLIO"; digitar "12345678900" acha "123.456.789-00".
- Quando o mesmo dado já existe escrito de formas diferentes, **as variantes são agrupadas numa sugestão só** e o sistema oferece a **grafia mais usada**; havendo empate, a mais completa (com acento e com pontuação). É a função `acMelhor()` com o critério `acRiqueza()`.
- O contador de lançamentos ajuda a identificar qual é a grafia "oficial" do cliente.
5. **Financeiro** (só gestão) — filtro por período pela **data de pagamento** (+ atalhos Este mês / Mês passado / Este ano / Todo o período), total pago, quantidade, clientes, valor médio, total por grupo, tabela e CSV com linha de total. Avisa quando há pago sem data.
6. **Painel de Usuários** (só gestão) — botão **"Usuários"** no topo. Lista todos (nome, e-mail, perfil colorido) e permite **criar**, **editar** (nome, perfil, senha opcional) e **excluir**. No atendimento o botão fica escondido.
7. **Modo claro/escuro** — botão no topo, salvo em localStorage por pessoa.
8. **Histórico** — botão no topo (últimas 150) + "última alteração por X em data" dentro de cada lançamento + histórico individual.
9. **Recibo de quitação** — botão por lançamento e "Recibo do cliente" (consolida vários processos, soma o total, caixinhas marcáveis; pendentes vêm marcados). Dados bancários (Chave Pix, Banco, Agência, Conta) salvos no lançamento. Documento pronto para imprimir/PDF.
10. **Backup** — botão baixa JSON com todos os registros. (Plano grátis do Supabase **não faz backup automático**.)

---

## 5. O recibo de quitação (detalhes importantes)

- Reproduz **fielmente** o modelo do escritório: logo CANAVERDE no topo e rodapé timbrado (telefone, e-mail, endereço), ambos embutidos em base64.
- **Texto mantido literal**, inclusive os erros de digitação do original: **"PRESTAÇAO"**, **"conta bancaria a baixo"**. *(Pendência: Danilo pode querer corrigir.)*
- **Comarca e Vara não existem** no recibo (removidos a pedido — o sistema não tem esses dados).
- **3 itens** numerados: quitação + prestação de contas / juros e correção + cláusula quarta / orientação e alcance da quitação.
- **Em negrito:** "Cliente:", "CPF/CNPJ:", "Número do processo:", "CANAVERDE & AGUIAR SOCIEDADE DE ADVOGADOS", todo o bloco de dados bancários, "Declaro, ainda, que com o recebimento do referido valor:" e os numerais (via `ol li::marker`).
- **Valor por extenso** em pt-BR — função `extensoReais()`, testada em 15+ casos (regras do "e", "cem/cento", "de reais" para milhão/bilhão exatos).
- Data no formato "São Paulo, 15 de Julho de 2026."
- Abre em nova janela (`window.open`) — **pop-ups precisam estar liberados**.
- O recibo abre em `about:blank`: **URL relativa não funciona lá dentro** (ver pendência 1).

---

## 6. Identidade visual

- **Emblema:** símbolo da Canaverde (círculo verde), no topo e no login. O antigo "MLE" foi removido.
- **Favicon (NOVO em 10/08/2026):** o ícone da aba do navegador é o **mesmo emblema do login**, no arquivo **`favicon.png`** (96×96, 8 KB) na raiz do repositório, referenciado por `<link rel="icon" type="image/png" href="/favicon.png">` no `<head>`.
  - É **arquivo separado, não base64** — de propósito: não engorda os HTML e é o primeiro passo da pendência 1 do §8.
  - O `favicon.png` foi gerado a partir do próprio base64 do emblema que já estava dentro do `index.html`, então é exatamente a mesma imagem.
  - Se um dia o arquivo sumir do repositório, o navegador volta a mostrar o ícone genérico (aquele globo) — nada quebra, só o ícone.
- **Nome e subtítulo (30/08/2026):** título **DANF**, subtítulo **Controle de Repasses**, e uma etiqueta ao lado do nome com **GESTÃO** ou **ATENDIMENTO**. A etiqueta existe porque o subtítulo ficou igual nos dois sistemas e sem ela ninguém saberia em qual está. **É essa etiqueta que o `transform.py` troca** (antes era o subtítulo).
- Cores: `--azul:#1a3a5c`, `--azul2:#2d6a9f`, `--azul-cl:#eaf2fa`. AG. PAGAMENTO usa `--agp-bg` / `--agp-borda`. Tema escuro via `[data-theme="dark"]` sobre variáveis CSS.

---

## 7. Estrutura técnica dos HTML (~225 KB cada, ~1450 linhas)

Arquivo único: `<style>` (variáveis CSS + tema escuro) → HTML (header, stats, filtros, wrap, modais: editar, histórico, recibo, **usuários**, login) → `<script>`.

Blocos do JS, na ordem:
config Supabase (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `_normUrl()`) → `MODE`/`isGestao`/`TABLE` → utilitários (`norm`, `parseComp`, `mesesPend`, `tempoCls`, `esc`, `brl`, `parseBR`, `fmtBR`) → **status (`ehAg`, `stCls`, `stLabel`, `stNext`, `stBtn`)** → **anexos / cliente / detalhes** → `loadData` → filtros → render (`renderStats`, `renderFlat`, `rowHTML`, `expHTML`, `renderCards`, `clRow`) → ações (`persist`, `toggleCp`, `togglePago`, `savePag`, `saveObs`, `delRec`) → modal (`openModal`, `saveModal`) → export (`doExportJSON`, `doExportCSV`) → `LOGO_B64`/`RODAPE_B64` → tema → extenso → auditoria (`openLog`) → financeiro (`renderFin`, `finPreset`, `exportFinCSV`) → recibo (`openRec`, `openRecCliente`, `buildRec`, `gerarRecibo`, `abrirRecibo`) → **usuários (`openSenhas`, `closeSenhas`, `renderUsuarios`, `formNovo`, `formEditar`, `mostrarForm`, `salvarUsuario`, `excluirUsuario`)** → login/init (`boot`, `doLogin`, `onLogged`, `canRefresh`, `doLogout`).

**Pontos-chave de perfil no código:**
- `const MODE` / `const isGestao` (linha ~372) — origem de tudo.
- `stBtn()` — **único lugar** que monta o status: `<button>` para a gestão, `<span>` para o atendimento. `rowHTML()` e `clRow()` só chamam essa função.
- `togglePago()` — trava por perfil logo na primeira linha; usa `stNext()` para girar o ciclo.
- Bloco final `if(!isGestao){...}` — esconde `btnFin` e `btnSenhas`.

**Pontos-chave dos anexos, cliente e detalhes (30/08/2026):**
- Bloco único logo antes de `/* ---------- dados (Supabase) ---------- */`. Guarda `ANEXOS`, `CLIENTES`, `CARDNN`, `MEU_EMAIL`, `MEU_NOME` e os ícones SVG (`SVG_OLHO`, `SVG_CLIPE`, `SVG_CIFRAO`, `SVG_BAIXAR`, `SVG_LIXO`, `SVG_ARQ`).
- `loadData()` agora chama `loadAnexos()` e `loadClientes()` **antes** de renderizar. Quem mexer em `loadData` precisa manter essa ordem.
- **`MEU_EMAIL` é obrigatório para anexar** — a policy do banco exige que `criado_por_email` seja o e-mail de quem está logado. Ele é buscado em `onLogged()` por `sb.rpc('meu_email')`. Se falhar, o botão avisa em vez de dar erro cru.
- Anexos: `openAnex` → `renderAnexos` → `enviarAnexo` / `baixarAnexo` / `excluirAnexo`. O download monta um `<a>` temporário com a URL assinada (não usa `window.open`, que o bloqueador de pop-up derruba).
- Detalhes: `openDet` / `openDetCliente` → `renderDet` → `renderDetLanc` / `renderDetCliente` → `salvarDet`. `renderDetCliente` depende de `CARDMAP`/`CARDNN`, que só existem depois de renderizar a visão *Por cliente* — e é só de lá que ela é aberta.
- `#ovAnex` tem `z-index:140` para ficar **por cima** da ficha de detalhes; sem isso, abrir anexos de dentro dos detalhes desenharia o painel atrás.

**Pontos-chave do saldo devedor:**
- `ehDevedor(r)`, `valorAberto(r)` e `totaisCliente(list)` concentram a conta. `totaisCliente` devolve `{rep, dev, liq}`.
- Quem consome: cartões do topo (`renderStats`), cartão do cliente (`renderCards`), ficha do cliente (`renderDetCliente`).
- Quem **exclui** devedor de propósito: `finRows` (Financeiro), `openRec` e `openRecCliente` (recibo).

**Pontos-chave do status de três estados:**
- Mexer no ciclo, nos rótulos ou nas cores = mexer **só** em `ehAg` / `stCls` / `stLabel` / `stNext` / `stBtn`. Tudo o mais (tabela, cartões, CSV, recibo) consome essas funções.
- Onde o status ainda aparece "cru": `applyFilters()` (filtro), `renderStats()` (cartões do topo), `renderCards()` (etiquetas do cliente), `savePag()` e `saveModal()` (gravação).
- CSS: `.stbtn.agp`, `.bdg.agp`, `.sc.agp`, `tbody tr.agp`, `.cl-row.agp` e o bloco do riscado (`tbody tr.pago .cli, .cpf, .proc, .reu, .comp, .val, .obs-s`).
- **C.P. tem dois níveis:** o do lançamento (`repasses.cp`, a caixinha da primeira coluna) e o do cliente (`clientes.cp`, na ficha do cliente). `ehCP(r)` junta os dois — é o que o filtro "Só C.P." e a contagem do topo usam. Quando o C.P. vem do cliente, aparece uma etiqueta ao lado do nome **e a caixinha de todos os processos dele aparece marcada** (30/08/2026).
  Nesse caso a caixinha fica **travada** (`disabled`), de propósito: desmarcar ali não faria efeito nenhum, porque a marcação vem do cliente. Para tirar, é em **Detalhes / OBS do cliente**, na visão *Por cliente*.
- **Código morto conhecido:** o ramo do atendimento em `expHTML()` e a função `saveObs()` não são mais alcançados — desde 30/08 a linha de expansão só é criada na gestão, e o atendimento salva observação pela ficha de Detalhes / OBS. Ficaram no arquivo de propósito, para não mexer no que não precisa.

**Os dois arquivos são gêmeos** — mudam só `<title>`, o subtítulo (2×) e `const MODE`.
**Basta trabalhar no `index.html`: o `atendimento.html` sai do `transform.py`.**

**Como validar antes de entregar:** extrair o último `<script>` e rodar `node --check`; opcionalmente um harness em Node com DOM/Supabase simulados (precisa stub de `confirm`, `alert`, `localStorage`, `window.matchMedia`, `window.open`, e `sb.from()` encadeável + `sb.rpc`).

**Validação melhor (usada em 10/08/2026):** subir a pasta num servidor local (`npx http-server -p 8099`) e abrir no Chromium com Playwright; esconder o `loginOv`, atribuir `RECORDS` direto (é `let` no topo do script, então dá para escrever nele pelo `page.evaluate`), chamar `buildFilterOptions()` e `render()`, e conferir por `getComputedStyle`. Assim se testa a tela de verdade — riscado, cores, celular, modo escuro — sem precisar de banco. O erro `ERR_TUNNEL_CONNECTION_FAILED` que aparece no console é só o CDN do `supabase-js` bloqueado no ambiente de teste; no site publicado ele carrega normalmente.

---

## 8. Pendências e próximos passos

1. **[PRIORIDADE] Emagrecer os arquivos** — ~107 KB dos 198 KB ainda são as imagens (logo, rodapé, emblema) em base64 dentro do HTML. Tirar para arquivos separados (`logo.png`, `rodape.png`, `emblema.png`) referenciados por **URL absoluta** (`new URL('logo.png', location.href).href` — atenção: o recibo abre em `about:blank`, então **URL relativa não funciona**). Resultado: HTML cai para ~90 KB e o app abre mais rápido.
   - **Primeiro passo já feito em 10/08/2026:** o `favicon.png` foi criado como arquivo separado (a partir do base64 do emblema), provando que serve arquivo estático na Vercel sem problema. Falta trocar os `<img>` do emblema e as duas imagens do recibo.
2. Corrigir (ou não) os erros de digitação do modelo do recibo ("PRESTAÇAO", "conta bancaria a baixo").
3. Decidir se o atendimento continua vendo valor no recibo (hoje vê; `recibo_dados` está concedida).
4. Backup automático: só no Supabase Pro (US$ 25/mês). Hoje o backup é manual pelo botão. Considerar rotina de backup agendada.
5. Avaliar remover a função legada `admin_definir_senha` (não é mais usada pela tela).
6. Permitir troca de e-mail de usuário (hoje exige excluir + recriar).
7. **Espaço do Storage:** o plano grátis do Supabase dá **1 GB** para anexos. Com comprovante em PDF (~200 KB) dá muito arquivo, mas foto de documento pesa bem mais. Vale olhar o consumo daqui a alguns meses — o painel do Supabase mostra em *Storage*.
8. **Anexo não entra no backup do botão.** O JSON baixa os lançamentos, não os arquivos. Se quiser backup dos anexos, precisa de uma rotina à parte.
9. **Feriado forense e ponto facultativo** não entram no cálculo da previsão (ver §3.1). Se atrapalhar na prática, trocar `eh_feriado_br` por uma tabela editável.
10. Limpar o código morto do `expHTML()` (ramo do atendimento) e o `saveObs()`.

---

## 9. Receitas úteis (Supabase)

**Testar migração sem gravar nada** — envolver em transação e dar `rollback` no fim:
```sql
drop table if exists _res;
create temp table _res(cenario text, resultado text);
do $$
begin
  -- simular usuário logado:
  perform set_config('request.jwt.claims',
    json_build_object('sub','<uuid-do-usuario>','role','authenticated')::text, true);
  begin
    -- ação a testar
    insert into _res values ('cenario X','OK');
  exception when others then
    insert into _res values ('cenario X','RECUSADO');
  end;
end $$;
select * from _res;
rollback;
```

**UUIDs úteis para teste:**
- Danilo (gestao): `f8186172-3101-42ab-a681-f0e897282efa`
- Anderson (atendimento): `f3da50f3-49a0-4dd1-876e-8a7f56fd8e15`

**Conferir estado antes de aplicar:** usar `information_schema.columns`, `pg_trigger`, `pg_policy`, `pg_proc`.

---

## 10. Armadilhas já vividas (não repetir)

- **`--` em SQL é comentário** — linhas assim não executam nada.
- **Nome de arquivo com `(1)`** (ex.: `index (1).html`) → Vercel devolve 404. Tem que ser exatamente `index.html` / `atendimento.html`.
- **Chave do Supabase:** projetos novos usam `sb_publishable_...` (não existe mais `anon`). Erro típico: "Invalid API key".
- **URL do Supabase:** é `https://xxx.supabase.co` — **não** a do painel (`supabase.com/dashboard/project/...`). Erro típico: "Invalid path specified in request URL (404)". Há um `_normUrl()` no código que conserta os casos comuns.
- **Publicar direto pela Vercel desincroniza o GitHub** — o próximo commit reverteria tudo. **O GitHub é a fonte da verdade.**
- **`auth.uid()` retorna null** em contexto service_role/postgres (sem JWT) — usado de propósito para migrações passarem pelas travas.
- **SECURITY DEFINER exige `set search_path`** explícito, senão o Supabase acusa no advisor.
- **`auth.identities.email` é coluna gerada** (`lower(identity_data->>'email')`) — **não** incluir em INSERT.
- **Criar usuário exige as duas tabelas:** `auth.users` **e** `auth.identities` (com `email_confirmed_at = now()`), senão o login do GoTrue não funciona.
- **Conector Supabase (MCP):** SQL com vários comandos só devolve o **último** resultado; `raise notice` dentro de `DO` **não aparece** — gravar numa temp table e dar `select`.
- **Contagem de bytes × caracteres:** o arquivo tem acentos (UTF-8), então `len()` em Python (caracteres) é menor que `wc -c` (bytes). Não é sinal de divergência.
- **Riscado (`text-decoration`) não se apaga por dentro.** Riscar o `<td>` inteiro e depois pôr `text-decoration:none` nos botões **não funciona** — em CSS o riscado desce para os filhos e o filho não consegue desfazer. Por isso o riscado é aplicado **direto nos textos** (`.cli`, `.cpf`, `.proc`, `.reu`, `.comp`, `.val`, `.obs-s`), e não no `<td>`.
- **E riscar o `<td>` também quebra no celular:** no modo estreito o `td` vira `display:flex`, e riscado **não desce** para filhos de um flex container. Ou seja: riscar o `td` sumiria justamente no celular. Mais um motivo para riscar os textos diretamente.
- **Foi preciso criar `<span class="comp">` e `<span class="obs-s">`** porque competência e observação eram texto solto dentro do `<td>` — texto solto não tem como receber estilo próprio.
- **`create or replace view` só acrescenta coluna no fim** e **apaga as opções da view se não forem repetidas** — por isso a `repasses_atendimento` é recriada sempre com `with (security_invoker = off)` explícito. As permissões (`grant`) sobrevivem, essas não precisam ser refeitas.
- **`set_config('request.jwt.claims', ..., true)` vale até o fim da transação**, não até o fim do bloco `DO`. Num teste com `rollback`, se você simular o atendimento dentro do `DO` e depois rodar um `update` de migração fora dele, esse update roda **como se fosse o atendimento** e é barrado pela trava. Zerar com `perform set_config('request.jwt.claims', null, true)` antes de sair.
- **Fechar a lista de sugestão no `blur` fecha a lista errada.** Ao pular do Réu para o Processo, o `blur` do Réu dispara um fechamento atrasado que apagava a lista que o Processo acabou de abrir — e o clique não preenchia nada. Por isso `acFechaDepois()` confere antes se o foco foi para outro campo com sugestão, e nesse caso não fecha.
- **Tabela larga estourava o enquadro da tela.** Com 6 botões de ação por linha, a tabela ficou maior que a janela e a **página inteira** passou a rolar para o lado. Corrigido em 30/08/2026 com `.wrap{overflow-x:auto}` (a tabela rola dentro da própria caixa, a página nunca sai do lugar) mais uma dieta: `padding` das células 10→8px, ícones 15→14px, `gap` dos botões 4→2px e a conta do "a pagar" podendo quebrar linha (era `nowrap` e sozinha exigia ~150px). Conferido por `document.documentElement.scrollWidth > clientWidth` a 1365px e a 1180px.
- **Não basta a página não rolar: a tabela também tem que caber.** Em 31/08/2026 o usuário reclamou de novo ("tela desenquadrou") mesmo com a página parada — o que rolava era a **caixa** da tabela, e ao arrastar para a direita o nome do cliente sumia. A conta é sempre a mesma: **largura mínima da tabela × espaço disponível** (`#wrap.clientWidth`, que é a janela menos o `padding` lateral). Numa tela de 1280px a gestão precisava de 1303px e sobrava 1236px. Corrigido com uma segunda dieta, toda cosmética: `padding` lateral das barras 22→14px (header, `.stats`, `.controls`, `.count` e `.wrap` **juntos**, senão a tabela desalinha das barras de cima), células e cabeçalho 8→5px, fonte do cabeçalho 10,5→10px com `letter-spacing` .5→.2px, `.proc` 11,5→11px, `.cpf` 12→11,5px, `.gtag` com 7px de padding e `.ico` com 3px (no celular volta a 5px + ícone de 16px, senão fica difícil de acertar com o dedo). **Resultado medido com 272 lançamentos:** a gestão precisa de 1121px (cabe de 1152px para cima, depois de juntar Competência com Tempo pendente) e o atendimento de 997px (cabe de 1024px para cima). Testado em `flat`, `cli` e `fin`, nos dois perfis, de 1024 a 1920px.
- **A previsão ao lado do status custava ~90px de largura.** Na coluna Status, a etiqueta AG. PAGAMENTO e o "prev. 18/09/2026" ficavam **lado a lado**, porque `.prev` era `display:inline-block`. A coluna pedia 201px; empilhando a previsão embaixo (`<div class="prevw">`, 01/09/2026) passou a pedir 118px. Mesma informação, 83px a menos.
- **O navegador reparte a sobra de largura em proporção ao texto mais comprido de cada coluna.** Por isso a razão social do réu ("ANDOCARD ADMINISTRADORA DE CARTOES LTDA.") ganhava mais espaço que o **nome do cliente** — a 1280px eram 207px para o réu contra 179px para o cliente, que é o que mais se lê. Corrigido em 01/09/2026 com dicas de largura no `<th>` (`Cliente` 19%, `Réu` 14% na gestão; 22% e 17% no atendimento), que passaram a 225px e 170px. **Não são larguras fixas** — em `table-layout:auto` o navegador trata como preferência e continua distribuindo o resto; por isso a tabela segue se adaptando de 1024 a 1920px.
- **Competência e Tempo pendente viraram uma coluna só** (01/09/2026, a pedido). A pastilha do tempo passou a aparecer **embaixo** da competência, dentro da mesma célula (`<div class="tp">`). Foi a maior economia de largura de todas: a lista da gestão caiu de **1234px para 1121px** e passou a caber a partir de 1152px, e o que sobrou foi para o nome do cliente e o réu (de 3 e 4 linhas para 2 e 3).
  - **A ordenação não se perdeu:** tempo pendente é calculado a partir da competência, então as duas ordens são a mesma fila, só que ao contrário — o próprio clique no cabeçalho inverte. Por isso a chave de ordenação `meses` foi removida de `sortRecs` (ficou inalcançável).
  - **Tempo pendente continua existindo** como linha própria na ficha de Detalhes / OBS e como coluna própria no CSV — lá não há disputa de largura.
  - No **celular** a célula vira uma linha de flex: `COMPETÊNCIA | Ago/2026 | [4 anos e 3 meses]`, tudo numa linha só. Ficou melhor do que antes, que eram duas.
- **Deixar `thead th` quebrar linha não vale a pena.** Tirar o `white-space:nowrap` do cabeçalho economiza 27px, **mas joga as setinhas de ordenação para uma segunda linha** e o cabeçalho fica feio e mais alto. Testado e descartado em 31/08/2026.
- **Ordem dos triggers é alfabética pelo nome.** `trg_normaliza_status` roda depois de `trg_bloqueia_pagamento` de propósito: primeiro barra quem não pode, depois arruma o dado.
- **Formulário que envia campo travado dá erro na cara do usuário.** Quando o atendimento edita um lançamento **já pago**, a tela não pode mandar `pago`/`valor_pago`/`previsao_pagamento` — nem com o mesmo valor de antes, porque o trigger compara e recusa. Por isso o `select` de status **some** nesse caso, em vez de aparecer desabilitado.
- **Data no banco é UTC.** A previsão usa `(now() at time zone 'America/Sao_Paulo')::date`; sem isso, das 21h em diante o banco já estaria no dia seguinte e a regra do "até o dia 15" erraria na virada do mês.
- **Recibo do cliente sai com o saldo devedor descontado** (30/08/2026). O valor final e o extenso já vêm líquidos. Uma caixinha no formulário (`rc_abate`, marcada por padrão) permite desmarcar — necessário quando o mesmo saldo devedor já foi abatido em outro recibo, já que o desconto é aplicado por recibo e não há controle de "já usado". Funções: `devedorDoCliente()`, `recBruto()`, `recDesconto()`, `recLiquido()`.
- **`create or replace view` não deixa apagar nem reordenar coluna**, só acrescentar no fim. Por isso `ag_pagamento`, `natureza`, `tipo_devedor` e `previsao_pagamento` estão no fim da `repasses_atendimento`, fora da ordem da tabela. É normal.
- **Bloqueador de pop-up derruba `window.open` depois de um `await`.** O download de anexo monta um `<a target="_blank">` temporário e clica nele — foi o único jeito confiável.
- **O `sb.storage` do supabase-js NÃO mandava o token de quem está logado** (30/08/2026). As chamadas de banco (`/rest/v1/...`) iam com o usuário; as de arquivo (`/storage/v1/...`) iam como visitante anônimo, e o Storage recusava com *"new row violates row-level security policy"* — que parece erro de permissão mal configurada, mas não é. **Diagnóstico:** comparar as duas no log (`edge_logs`, campo `request.sb.auth_user`) — numa aparece o usuário, na outra vem vazio. **Solução adotada:** falar com a API de arquivos por `fetch`, montando os cabeçalhos na mão (`apikey` + `Authorization: Bearer <access_token>`), em `enviarAnexo`, `baixarAnexo` e `excluirAnexo`. Não depende da versão da biblioteca.
- **Bucket privado exige URL assinada.** `POST /storage/v1/object/sign/anexos/<caminho>` com `{"expiresIn":120}` devolve `{"signedURL":"/object/sign/..."}` — a URL final é `_URL + '/storage/v1' + signedURL`, mais `&download=<nome>` para baixar com o nome certo. Link direto não abre, e é isso que se quer: documento de cliente não fica público.
- **Sessão vencida fazia o sistema insistir para sempre.** O `loadData` roda de 30 em 30 segundos; com o token vencido eram 73 recusas seguidas no log de 30/08/2026. Agora `sessaoCaiu()` reconhece o 401 e `sessaoExpirou()` para o relógio e traz a tela de login de volta, em vez de piscar erro vermelho a cada meio minuto.
- **Temp table em teste com `set local role authenticated`** precisa de `grant all on _res to authenticated`, senão o teste falha com "permission denied for table _res" e parece que a policy é que quebrou.
- **No teste como atendimento, leia pela view, não pela tabela.** Um `select ... from public.repasses` rodando com `set local role authenticated` e um usuário de atendimento devolve **zero linhas** (a policy `repasses_gestao` barra), e a variável fica nula — o teste acusa falha onde o sistema está certo. Use `public.repasses_atendimento`.
- **Caixinha de marcar dentro do modal esticava para 100%.** A regra `.modal-b .fld input{width:100%}` valia também para `input[type=checkbox]`, e o quadradinho ficava largo, jogando o rótulo para o meio da linha (o campo **C.P.** já sofria disso). Corrigido em 31/08/2026 com `.modal-b .fld input[type=checkbox]{width:18px;flex:none}`.

---

## 11. Como trabalhar

**Fluxo com Claude Code (atual):** o Claude Code tem a pasta e o Git. Editar `index.html` → `python3 transform.py` → `node --check` → commit → a Vercel republica em ~30s.

**Fluxo manual (fallback, sem Claude Code):** baixar os dois HTML → GitHub → *Add file → Upload files* → *Commit*.
Mudanças de **banco** entram na hora (via Supabase); só o **frontend** exige o commit.

**Economia de contexto (o limite já estourou antes):**
- **Um chat por assunto.** Ao terminar, pedir o resumo atualizado deste documento.
- Trabalhar só no `index.html` (o gêmeo é derivado).
- **Prints só para erro visual**; para erro de sistema, o texto basta.
- **Juntar todos os pedidos numa mensagem só.**
