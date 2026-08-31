-- =====================================================================
-- MIGRAÇÕES APLICADAS EM 23/07/2026
-- Sistema de Repasses — Canaverde & Aguiar Advogados
-- Supabase project_id: maytgfyzvoufepaerwwn
--
-- ⚠️ ESTE ARQUIVO É DOCUMENTAÇÃO / REFERÊNCIA.
--    Tudo aqui JÁ ESTÁ APLICADO no banco de produção.
--    NÃO rodar de novo sem necessidade. Se rodar, é idempotente
--    (create or replace / drop trigger if exists), mas confira antes.
--
-- Ordem: 1) trava de pagamento  2) senha (legada)  3) lista de usuários
--        4) criar/atualizar/excluir usuário
-- =====================================================================


-- =====================================================================
-- 1) TRAVA DE PAGAMENTO — somente perfil 'gestao'
--    Enforcement no BANCO (vale para tela, view ou chamada direta à API).
-- =====================================================================
create or replace function public.bloqueia_pagamento_nao_gestao()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- Sem usuário logado (service_role / migrações): não interfere. Proposital.
  if v_uid is null then
    return new;
  end if;

  if public.meu_perfil() = 'gestao' then
    return new;
  end if;

  -- Daqui pra baixo: usuário logado que NÃO é gestão.
  if tg_op = 'INSERT' then
    if coalesce(new.pago, false) = true
       or nullif(btrim(coalesce(new.data_pagamento, '')), '') is not null
       or nullif(btrim(coalesce(new.valor_pago, '')), '') is not null then
      raise exception 'Somente a gestao pode registrar pagamento.'
        using errcode = '42501';
    end if;

  elsif tg_op = 'UPDATE' then
    if (new.pago is distinct from old.pago)
       or (coalesce(nullif(btrim(coalesce(new.data_pagamento,'')),''),'')
           is distinct from
           coalesce(nullif(btrim(coalesce(old.data_pagamento,'')),''),''))
       or (coalesce(nullif(btrim(coalesce(new.valor_pago,'')),''),'')
           is distinct from
           coalesce(nullif(btrim(coalesce(old.valor_pago,'')),''),'')) then
      raise exception 'Somente a gestao pode alterar o status de pagamento.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_bloqueia_pagamento on public.repasses;
create trigger trg_bloqueia_pagamento
before insert or update on public.repasses
for each row execute function public.bloqueia_pagamento_nao_gestao();

-- Função de trigger não precisa ser chamável via API.
revoke all on function public.bloqueia_pagamento_nao_gestao() from public, anon, authenticated;


-- =====================================================================
-- 2) TROCA DE SENHA (LEGADA)
--    Substituída por admin_atualizar_usuario. Mantida por compatibilidade.
--    A tela NÃO usa mais esta função. Pode ser removida no futuro.
-- =====================================================================
create or replace function public.admin_definir_senha(target_email text, nova_senha text)
returns text
language plpgsql
security definer
set search_path = extensions, public, pg_temp
as $$
declare
  v_id uuid;
  v_email text := lower(btrim(coalesce(target_email, '')));
begin
  if public.meu_perfil() is distinct from 'gestao' then
    raise exception 'Apenas o perfil gestao pode alterar senhas.' using errcode = '42501';
  end if;
  if v_email = '' then
    raise exception 'Informe o e-mail do usuario.' using errcode = '22023';
  end if;
  if nova_senha is null or length(nova_senha) < 6 then
    raise exception 'A nova senha precisa ter ao menos 6 caracteres.' using errcode = '22023';
  end if;

  select id into v_id from auth.users where lower(email) = v_email;
  if v_id is null then
    raise exception 'Usuario nao encontrado: %', v_email using errcode = 'P0002';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(nova_senha, extensions.gen_salt('bf')),
         updated_at = now()
   where id = v_id;

  return 'Senha alterada com sucesso para ' || v_email;
end;
$$;

revoke all on function public.admin_definir_senha(text, text) from public, anon;
grant execute on function public.admin_definir_senha(text, text) to authenticated;


-- =====================================================================
-- 3) LISTAR USUÁRIOS — somente 'gestao'
--    Necessária porque a RLS de profiles (policy perfil_proprio)
--    deixa cada usuário ver apenas o próprio registro.
-- =====================================================================
create or replace function public.listar_usuarios()
returns table(email text, nome text, perfil text)
language sql
security definer
set search_path = public, pg_temp
as $$
  select p.email, p.nome, p.perfil
  from public.profiles p
  where public.meu_perfil() = 'gestao'
  order by p.email
$$;

revoke all on function public.listar_usuarios() from public, anon;
grant execute on function public.listar_usuarios() to authenticated;


-- =====================================================================
-- 4) CRIAR USUÁRIO — somente 'gestao'
--    Cria em auth.users + auth.identities e ajusta profiles.
--    OBS: auth.identities.email é coluna GERADA — nunca incluir no INSERT.
-- =====================================================================
create or replace function public.admin_criar_usuario(
  p_email text, p_nome text, p_senha text, p_perfil text)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_email  text := lower(btrim(coalesce(p_email,'')));
  v_nome   text := btrim(coalesce(p_nome,''));
  v_perfil text := lower(btrim(coalesce(p_perfil,'atendimento')));
  v_id     uuid := gen_random_uuid();
begin
  if public.meu_perfil() is distinct from 'gestao' then
    raise exception 'Apenas o perfil gestao pode gerenciar usuarios.' using errcode='42501';
  end if;
  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'Informe um e-mail valido.' using errcode='22023';
  end if;
  if v_perfil not in ('gestao','atendimento') then
    raise exception 'Perfil invalido (use gestao ou atendimento).' using errcode='22023';
  end if;
  if p_senha is null or length(p_senha) < 6 then
    raise exception 'A senha precisa ter ao menos 6 caracteres.' using errcode='22023';
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'Ja existe um usuario com este e-mail: %', v_email using errcode='23505';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token,
    raw_app_meta_data, raw_user_meta_data
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    v_email, extensions.crypt(p_senha, extensions.gen_salt('bf')),
    now(), now(), now(),
    '', '', '', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('email_verified', true, 'name', v_nome)
  );

  insert into auth.identities (
    provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    v_id::text, v_id,
    jsonb_build_object('sub', v_id::text, 'email', v_email,
                       'email_verified', false, 'phone_verified', false),
    'email', now(), now(), now()
  );

  -- o trigger handle_new_user já criou o profile; aqui ajusta nome/perfil/email
  update public.profiles
     set nome = nullif(v_nome,''), perfil = v_perfil, email = v_email
   where id = v_id;

  return 'Usuario criado: ' || v_email;
end;
$$;


-- =====================================================================
-- 5) ATUALIZAR USUÁRIO — somente 'gestao'
--    Nome + perfil sempre; senha só se p_nova_senha vier preenchida.
--    E-mail NÃO é alterável (é a chave de login).
-- =====================================================================
create or replace function public.admin_atualizar_usuario(
  p_email text, p_nome text, p_perfil text, p_nova_senha text default null)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_email        text := lower(btrim(coalesce(p_email,'')));
  v_nome         text := btrim(coalesce(p_nome,''));
  v_perfil       text := lower(btrim(coalesce(p_perfil,'')));
  v_id           uuid;
  v_perfil_atual text;
begin
  if public.meu_perfil() is distinct from 'gestao' then
    raise exception 'Apenas o perfil gestao pode gerenciar usuarios.' using errcode='42501';
  end if;
  if v_perfil not in ('gestao','atendimento') then
    raise exception 'Perfil invalido (use gestao ou atendimento).' using errcode='22023';
  end if;

  select p.id, p.perfil into v_id, v_perfil_atual
  from public.profiles p where lower(p.email) = v_email;
  if v_id is null then
    raise exception 'Usuario nao encontrado: %', v_email using errcode='P0002';
  end if;

  -- não deixar o sistema sem nenhum gestor
  if v_perfil_atual = 'gestao' and v_perfil = 'atendimento'
     and (select count(*) from public.profiles where perfil='gestao') <= 1 then
    raise exception 'Nao e possivel rebaixar o unico usuario gestao.' using errcode='42501';
  end if;

  update public.profiles
     set nome = nullif(v_nome,''), perfil = v_perfil
   where id = v_id;

  if p_nova_senha is not null and btrim(p_nova_senha) <> '' then
    if length(p_nova_senha) < 6 then
      raise exception 'A nova senha precisa ter ao menos 6 caracteres.' using errcode='22023';
    end if;
    update auth.users
       set encrypted_password = extensions.crypt(p_nova_senha, extensions.gen_salt('bf')),
           updated_at = now()
     where id = v_id;
  end if;

  return 'Usuario atualizado: ' || v_email;
end;
$$;


-- =====================================================================
-- 6) EXCLUIR USUÁRIO — somente 'gestao'
--    profiles sai por cascata (FK profiles_id_fkey ON DELETE CASCADE).
-- =====================================================================
create or replace function public.admin_excluir_usuario(p_email text)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_email  text := lower(btrim(coalesce(p_email,'')));
  v_id     uuid;
  v_perfil text;
begin
  if public.meu_perfil() is distinct from 'gestao' then
    raise exception 'Apenas o perfil gestao pode gerenciar usuarios.' using errcode='42501';
  end if;

  select p.id, p.perfil into v_id, v_perfil
  from public.profiles p where lower(p.email) = v_email;
  if v_id is null then
    raise exception 'Usuario nao encontrado: %', v_email using errcode='P0002';
  end if;

  if v_id = auth.uid() then
    raise exception 'Voce nao pode excluir a propria conta.' using errcode='42501';
  end if;
  if v_perfil = 'gestao'
     and (select count(*) from public.profiles where perfil='gestao') <= 1 then
    raise exception 'Nao e possivel excluir o unico usuario gestao.' using errcode='42501';
  end if;

  delete from auth.identities where user_id = v_id;
  delete from auth.users where id = v_id;  -- cascata remove o profile

  return 'Usuario excluido: ' || v_email;
end;
$$;


-- =====================================================================
-- PERMISSÕES das funções de usuário
-- =====================================================================
revoke all on function public.admin_criar_usuario(text,text,text,text)     from public, anon;
revoke all on function public.admin_atualizar_usuario(text,text,text,text) from public, anon;
revoke all on function public.admin_excluir_usuario(text)                  from public, anon;
grant execute on function public.admin_criar_usuario(text,text,text,text)     to authenticated;
grant execute on function public.admin_atualizar_usuario(text,text,text,text) to authenticated;
grant execute on function public.admin_excluir_usuario(text)                  to authenticated;


-- =====================================================================
-- CONFERÊNCIA RÁPIDA (rodar isto é seguro — só lê)
-- =====================================================================
-- select p.proname, pg_get_function_identity_arguments(p.oid), p.prosecdef
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname='public' and p.proname like 'admin\_%' or p.proname='listar_usuarios'
-- order by p.proname;
--
-- select tgname from pg_trigger
-- where tgrelid='public.repasses'::regclass and not tgisinternal order by tgname;
-- Esperado: trg_bloqueia_pagamento, trg_marca_autor, trg_registra_log


-- =====================================================================
-- =====================================================================
-- MIGRAÇÕES APLICADAS EM 10/08/2026
-- Terceiro status: AG. PAGAMENTO
--
-- ⚠️ JÁ APLICADO no banco de produção. Idempotente, mas confira antes.
--
-- Ordem: 5) coluna ag_pagamento  6) trava de pagamento (atualizada)
--        7) normalização do status  8) view do atendimento (atualizada)
--        9) histórico (atualizado)
-- =====================================================================


-- =====================================================================
-- 5) COLUNA ag_pagamento — aditiva, não recria nada
--    Status = derivado de duas colunas booleanas:
--      pago = true                        -> PAGO
--      pago = false e ag_pagamento = true -> AG. PAGAMENTO
--      as duas false                      -> PENDENTE
-- =====================================================================
alter table public.repasses
  add column if not exists ag_pagamento boolean not null default false;

comment on column public.repasses.ag_pagamento is
  'true = lancamento separado, aguardando o pagamento programado. Sempre false quando pago = true.';


-- =====================================================================
-- 6) TRAVA DE PAGAMENTO — agora também protege ag_pagamento
--    Substitui a versão de 23/07/2026 (item 1 deste arquivo).
-- =====================================================================
create or replace function public.bloqueia_pagamento_nao_gestao()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
begin
  -- Sem usuario logado (operacoes administrativas / service_role): nao interfere.
  if v_uid is null then return new; end if;

  -- Gestao pode tudo.
  if public.meu_perfil() = 'gestao' then return new; end if;

  -- Daqui pra baixo: usuario logado que NAO e gestao (ex.: atendimento).
  if tg_op = 'INSERT' then
    if coalesce(new.pago, false) = true
       or coalesce(new.ag_pagamento, false) = true
       or nullif(btrim(coalesce(new.data_pagamento, '')), '') is not null
       or nullif(btrim(coalesce(new.valor_pago, '')), '') is not null then
      raise exception 'Somente a gestao pode registrar pagamento.' using errcode = '42501';
    end if;

  elsif tg_op = 'UPDATE' then
    if (new.pago is distinct from old.pago)
       or (coalesce(new.ag_pagamento,false) is distinct from coalesce(old.ag_pagamento,false))
       or (coalesce(nullif(btrim(coalesce(new.data_pagamento,'')),''),'')
           is distinct from coalesce(nullif(btrim(coalesce(old.data_pagamento,'')),''),''))
       or (coalesce(nullif(btrim(coalesce(new.valor_pago,'')),''),'')
           is distinct from coalesce(nullif(btrim(coalesce(old.valor_pago,'')),''),'')) then
      raise exception 'Somente a gestao pode alterar o status de pagamento.' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$function$;


-- =====================================================================
-- 7) NORMALIZAÇÃO — um lançamento pago não continua "aguardando pagamento"
--    Roda DEPOIS da trava (ordem alfabética dos triggers:
--    trg_bloqueia_pagamento -> trg_marca_autor -> trg_normaliza_status).
-- =====================================================================
create or replace function public.normaliza_status_repasse()
returns trigger language plpgsql set search_path to 'public','pg_temp'
as $function$
begin
  if new.ag_pagamento is null then new.ag_pagamento := false; end if;
  if coalesce(new.pago,false) then new.ag_pagamento := false; end if;
  return new;
end;
$function$;

drop trigger if exists trg_normaliza_status on public.repasses;
create trigger trg_normaliza_status
before insert or update on public.repasses
for each row execute function public.normaliza_status_repasse();


-- =====================================================================
-- 8) VIEW DO ATENDIMENTO — ganha ag_pagamento, continua SEM valores
--    A coluna nova entra no FIM (create or replace view só permite acrescentar).
-- =====================================================================
create or replace view public.repasses_atendimento
with (security_invoker = off) as
select id, nome, nome_norm, cpf, processo, reu, grupo, advogado, tipo, conta,
       competencia, ano, mes, busca, cp, pago, data_pagamento, obs,
       pix_chave, pix_banco, pix_agencia, pix_conta, atualizado_por, atualizado_em, criado_em,
       ag_pagamento
from public.repasses;


-- =====================================================================
-- 9) HISTÓRICO — passa a registrar mudanças de ag_pagamento
--    Único ponto alterado: 'ag_pagamento' entrou no array 'campos'.
-- =====================================================================
create or replace function public.registra_log()
returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare
  quem_e  text := coalesce(public.meu_email(), 'sistema');
  nome_e  text := coalesce(public.meu_nome(),  'sistema');
  campos  text[] := array['nome','cpf','processo','reu','grupo','advogado','tipo','conta',
                          'competencia','ano','mes','valor_num','cp','pago','ag_pagamento',
                          'data_pagamento','valor_pago','obs','pix_chave','pix_banco',
                          'pix_agencia','pix_conta'];
  c       text;
  v_old   text;
  v_new   text;
  j_old   jsonb;
  j_new   jsonb;
begin
  if (TG_OP = 'INSERT') then
    insert into public.repasses_log (repasse_id, cliente, processo, acao, quem_email, quem_nome)
    values (new.id, new.nome, new.processo, 'criou', quem_e, nome_e);
    return new;

  elsif (TG_OP = 'DELETE') then
    insert into public.repasses_log (repasse_id, cliente, processo, acao, quem_email, quem_nome)
    values (old.id, old.nome, old.processo, 'excluiu', quem_e, nome_e);
    return old;

  else
    j_old := to_jsonb(old);
    j_new := to_jsonb(new);
    foreach c in array campos loop
      v_old := j_old ->> c;
      v_new := j_new ->> c;
      if (v_old is distinct from v_new) then
        insert into public.repasses_log
          (repasse_id, cliente, processo, acao, campo, valor_antigo, valor_novo, quem_email, quem_nome)
        values (new.id, new.nome, new.processo, 'alterou', c,
                coalesce(v_old,''), coalesce(v_new,''), quem_e, nome_e);
      end if;
    end loop;
    return new;
  end if;
end $function$;


-- =====================================================================
-- CONFERÊNCIA RÁPIDA da migração de 10/08/2026 (só lê, é seguro)
-- =====================================================================
-- select column_name from information_schema.columns
-- where table_schema='public' and table_name='repasses' and column_name='ag_pagamento';
-- Esperado: 1 linha.
--
-- select tgname from pg_trigger
-- where tgrelid='public.repasses'::regclass and not tgisinternal order by tgname;
-- Esperado: trg_bloqueia_pagamento, trg_marca_autor, trg_normaliza_status, trg_registra_log
--
-- select count(*) from information_schema.columns
-- where table_schema='public' and table_name='repasses_atendimento'
--   and column_name in ('valor_num','valor_pago');
-- Esperado: 0 (o atendimento continua sem ver dinheiro).


-- =====================================================================
-- =====================================================================
-- MIGRAÇÕES APLICADAS EM 30/08/2026 (DANF)
-- Anexos, saldo devedor, previsão de pagamento e dados do cliente
--
-- ⚠️ JÁ APLICADO no banco de produção. Idempotente, mas confira antes.
--
-- Itens: 10) feriados e "dia 20 útil"   11) colunas novas em repasses
--        12) tabela clientes            13) tabela anexos + bucket
--        14) trava de pagamento (3ª versão)
--        15) normalização + previsão automática
--        16) view do atendimento        17) histórico
--
-- O SQL completo está no commit desta data. Os pontos que mais importam:
-- =====================================================================

-- 10) Feriados: nacionais + municipal de SP (25/01) + estadual de SP (09/07),
--     mais os móveis (Carnaval, Sexta-feira Santa e Corpus Christi) calculados
--     a partir da Páscoa. Funções: pascoa_br, eh_feriado_br, dia_util_anterior.
--
--     previsao_dia20(data): até o dia 15 vai para o dia 20 do próprio mês;
--     do dia 16 em diante vai para o dia 20 do mês seguinte; se cair em fim de
--     semana ou feriado, antecipa para o dia útil anterior.
--     Conferido: 05/09/2026 -> 18/09/2026 (o dia 20 é domingo).

-- 11) alter table public.repasses
--       add column if not exists natureza text not null default 'repasse',
--       add column if not exists tipo_devedor text,
--       add column if not exists previsao_pagamento date;
--     + check em natureza ('repasse','devedor')
--     + check em tipo_devedor (Custas, Má-Fé, Réu, Indenização, Escritório, Estado)

-- 12) public.clientes (nome_norm pk, nome, obs, cp, atualizado_por, atualizado_em)
--     RLS: quem está logado lê, cria e atualiza; só a gestão exclui.
--     Trigger trg_marca_autor_cliente carimba quem mexeu.

-- 13) public.anexos (repasse_id nulo = anexo geral do cliente) + bucket
--     privado 'anexos' no Storage.
--     RLS: todo mundo logado LÊ; ao inserir, criado_por_email tem que ser o
--     e-mail de quem está logado; excluir só a gestão OU quem enviou.
--     As mesmas regras valem no Storage (policies anexos_obj_*).

-- 14) bloqueia_pagamento_nao_gestao: o atendimento AGORA PODE mudar
--     ag_pagamento (era barrado desde 10/08). Continua barrado em
--     pago, data_pagamento, valor_pago e previsao_pagamento manual.

-- 15) normaliza_status_repasse: pago = true zera ag_pagamento; virar
--     AG. PAGAMENTO sem previsão agenda o próximo dia 20 útil (no fuso
--     America/Sao_Paulo); voltar para PENDENTE limpa a previsão;
--     natureza 'repasse' limpa tipo_devedor.

-- 16) repasses_atendimento ganhou natureza, tipo_devedor e previsao_pagamento.
--     Continua SEM valor_num e SEM valor_pago.

-- 17) registra_log passou a gravar previsao_pagamento, natureza e tipo_devedor.


-- =====================================================================
-- CONFERÊNCIA RÁPIDA da migração de 30/08/2026 (só lê, é seguro)
-- =====================================================================
-- select column_name from information_schema.columns
--  where table_schema='public' and table_name='repasses'
--    and column_name in ('natureza','tipo_devedor','previsao_pagamento');
-- Esperado: 3 linhas.
--
-- select tgname from pg_trigger
--  where tgrelid='public.repasses'::regclass and not tgisinternal order by tgname;
-- Esperado: trg_bloqueia_pagamento, trg_marca_autor, trg_normaliza_status, trg_registra_log
--
-- select id, public.eh_feriado_br(date '2026-12-25') as natal_e_feriado,
--        public.previsao_dia20(date '2026-09-05') as deve_dar_18_09
--   from storage.buckets where id='anexos';
-- Esperado: uma linha, 'anexos', true, 2026-09-18.
--
-- select policyname from pg_policies
--  where schemaname='storage' and tablename='objects' and policyname like 'anexos_obj%';
-- Esperado: anexos_obj_envia, anexos_obj_exclui, anexos_obj_leitura


-- =====================================================================
-- MIGRAÇÃO APLICADA EM 30/08/2026 (parte 2)
-- Saldo devedor sem status nem previsão de pagamento
-- =====================================================================
-- 18) normaliza_status_repasse: para natureza = 'devedor', zera pago,
--     ag_pagamento, previsao_pagamento, data_pagamento e valor_pago.
--     Saldo devedor serve só para abater de repasses e como informação.
--
-- 19) bloqueia_pagamento_nao_gestao: passa a recusar que quem não é gestão
--     converta um lançamento JÁ PAGO em saldo devedor — pela regra 18 isso
--     zeraria o pagamento sem passar pela trava.
--
-- 20) Ajuste de dados (rodou uma vez):
--     update public.repasses
--        set previsao_pagamento = public.previsao_dia20(
--              (now() at time zone 'America/Sao_Paulo')::date)
--      where natureza <> 'devedor' and ag_pagamento and previsao_pagamento is null;
--     -- 2 lançamentos estavam em AG. PAGAMENTO desde antes da regra do dia 20
--     -- e ficaram sem previsão. Receberam 18/09/2026.
--
--     update public.repasses
--        set pago = false, ag_pagamento = false, previsao_pagamento = null
--      where natureza = 'devedor'
--        and (pago or ag_pagamento or previsao_pagamento is not null);
--     -- limpeza preventiva; não havia nenhum nessa situação.


-- =====================================================================
-- MIGRAÇÃO APLICADA EM 30/08/2026 (parte 3)
-- Atendimento vê o valor do saldo devedor + correção de regressão
-- =====================================================================
-- 21) repasses_atendimento passa a expor valor_num APENAS do saldo devedor:
--       case when natureza = 'devedor' then valor_num else null end as valor_num
--     Por ser coluna calculada, o Postgres a torna não atualizável — o
--     atendimento lê, mas não grava valor nem por chamada direta à API.
--     valor_pago continua totalmente fora da view.
--
-- 22) CORREÇÃO DE REGRESSÃO em bloqueia_pagamento_nao_gestao():
--     a migração 19 (saldo_devedor_sem_status_nem_previsao) reintroduziu por
--     engano a trava de ag_pagamento, e o atendimento ficou sem conseguir
--     mover um lançamento entre PENDENTE e AG. PAGAMENTO.
--     ag_pagamento NÃO deve constar na lista de campos bloqueados do UPDATE.
--
-- Conferência rápida (só lê):
-- select position('new.ag_pagamento,false) is distinct from coalesce(old.ag_pagamento'
--          in pg_get_functiondef(p.oid)) > 0 as bloqueia_ag_pagamento
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname='public' and p.proname='bloqueia_pagamento_nao_gestao';
-- Esperado: false.


-- =====================================================================
-- MIGRAÇÃO APLICADA EM 31/08/2026
-- saldo_devedor_quitado — dar um saldo devedor por quitado
-- =====================================================================
-- Testada com 6 cenários dentro de uma transação com rollback antes de
-- ser aplicada de verdade, incluindo a guarda de regressão do ag_pagamento.
--
-- 23) alter table public.repasses
--       add column if not exists devedor_quitado boolean not null default false;
--
-- 24) create index if not exists repasses_devedor_aberto_idx
--       on public.repasses (nome_norm)
--      where natureza = 'devedor' and devedor_quitado = false;
--
-- 25) normaliza_status_repasse(): um lançamento de natureza 'repasse'
--     tem devedor_quitado zerado à força. Só saldo devedor pode ficar quitado.
--
-- 26) bloqueia_pagamento_nao_gestao(): devedor_quitado entra na lista de
--     campos que só a gestão altera (INSERT e UPDATE).
--     ⚠️ ag_pagamento continua FORA da lista, de propósito — ver migração 22.
--     O código traz esse aviso como comentário dentro da própria função.
--
-- 27) repasses_atendimento: coluna devedor_quitado acrescentada no fim
--     (o atendimento vê a situação do saldo, mas a trava impede que grave).
--
-- 28) registra_log(): devedor_quitado passa a ser auditado como os demais.
--
-- Conferência rápida (só lê):
-- select table_name, column_name
--   from information_schema.columns
--  where column_name = 'devedor_quitado'
--  order by table_name;
-- Esperado: repasses e repasses_atendimento.
