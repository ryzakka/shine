-- Shine v0.2: multiplayer 1 vs 1 dengan 3 tokoh setiap sisi.
-- Jalankan SEKALI dari Supabase SQL Editor oleh pemilik proyek.
-- Jangan berikan kunci service_role kepada aplikasi Flutter.

create table if not exists public.shine_characters (
  id text primary key,
  name text not null,
  hp integer not null check (hp > 0),
  attack integer not null check (attack >= 0),
  skill_name text not null,
  skill_kind text not null check (skill_kind in
    ('damage','pierce','heal','heal_all','shield','reserve','drain','recoil','conditional_damage','hybrid')),
  skill_cost integer not null check (skill_cost between 1 and 4),
  skill_cooldown integer not null check (skill_cooldown between 1 and 8),
  skill_value integer not null check (skill_value >= 0),
  skill_aux integer not null default 0 check (skill_aux >= 0)
);

create table if not exists public.shine_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-F0-9]{6}$'),
  host_id uuid not null references auth.users(id),
  guest_id uuid references auth.users(id),
  host_cards text[] not null,
  guest_cards text[],
  status text not null default 'waiting' check (status in ('waiting','playing','finished')),
  state jsonb,
  revision integer not null default 0,
  created_at timestamptz not null default now(),
  constraint no_self_match check (guest_id is null or host_id <> guest_id)
);

create index if not exists shine_rooms_host_idx on public.shine_rooms(host_id);
create index if not exists shine_rooms_guest_idx on public.shine_rooms(guest_id);

alter table public.shine_characters enable row level security;
alter table public.shine_rooms enable row level security;

drop policy if exists shine_characters_read on public.shine_characters;
create policy shine_characters_read on public.shine_characters
  for select to authenticated using (true);
drop policy if exists shine_rooms_members_read on public.shine_rooms;
create policy shine_rooms_members_read on public.shine_rooms
  for select to authenticated
  using ((select auth.uid()) = host_id or (select auth.uid()) = guest_id);

-- Read-only for clients. Mutations ONLY through authorized definer RPCs.
revoke all on public.shine_rooms from anon, authenticated;
grant select on public.shine_rooms to authenticated;
revoke all on public.shine_characters from anon, authenticated;
grant select on public.shine_characters to authenticated;

-- Helper called only from privileged RPC; not exposed to clients.
create or replace function public.shine_validate_lineup(p_cards text[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_cards is null or cardinality(p_cards) <> 3 or
    (select count(distinct cid) from unnest(p_cards) as cid) <> 3 or
    (select count(*) from unnest(p_cards) as cid
     join public.shine_characters c on c.id=cid) <> 3 then
    raise exception 'Pilih tepat 3 tokoh berbeda yang tersedia.';
  end if;
end;
$$;

create or replace function public.shine_make_team(p_cards text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_fighters jsonb;
begin
  select jsonb_agg(jsonb_build_object(
    'id', c.id, 'hp', c.hp, 'max_hp', c.hp, 'atk', c.attack, 'cd', 0)
    order by u.ord)
  into v_fighters
  from unnest(p_cards) with ordinality as u(cid, ord)
  join public.shine_characters c on c.id=u.cid;
  return jsonb_build_object('cards',v_fighters,'active',0,'reserve',0,'block',0);
end;
$$;

create or replace function public.shine_create_room(p_cards text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_code text; v_attempt integer;
begin
  if (select auth.uid()) is null then raise exception 'Masuk terlebih dahulu.'; end if;
  perform public.shine_validate_lineup(p_cards);
  for v_attempt in 1..12 loop
    v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
    begin
      insert into public.shine_rooms(code,host_id,host_cards)
      values (v_code,(select auth.uid()),p_cards) returning id into v_id;
      return jsonb_build_object('id',v_id,'code',v_code);
    exception when unique_violation then
      null; -- Ulangi ketika kode undangan sudah digunakan.
    end;
  end loop;
  raise exception 'Tidak dapat membuat kode ruang. Coba lagi.';
end;
$$;

create or replace function public.shine_join_room(p_code text, p_cards text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.shine_rooms%rowtype; v_state jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Masuk terlebih dahulu.'; end if;
  perform public.shine_validate_lineup(p_cards);
  select * into v_room from public.shine_rooms
    where code = upper(trim(p_code)) for update;
  if not found then raise exception 'Kode ruang tidak ditemukan.'; end if;
  if v_room.host_id=(select auth.uid()) then raise exception 'Host tidak dapat bergabung sebagai tamu.'; end if;
  if v_room.status <> 'waiting' or v_room.guest_id is not null then
    raise exception 'Ruang sudah penuh atau pertandingan berjalan.';
  end if;
  v_state := jsonb_build_object(
    'turn',1,'winner',null,'log','Pertandingan dimulai!',
    'teams',jsonb_build_array(
      public.shine_make_team(v_room.host_cards), public.shine_make_team(p_cards)));
  update public.shine_rooms
    set guest_id=(select auth.uid()),guest_cards=p_cards,status='playing',
        state=v_state, revision=revision+1 where id=v_room.id;
  return jsonb_build_object('id',v_room.id,'code',v_room.code);
end;
$$;

-- Resolusi serangan, kemampuan, pergantian, cooldown dan KO dilakukan dalam satu transaksi.
create or replace function public.shine_submit_action(
  p_room_id uuid, p_expected_revision integer,
  p_attack integer default 0, p_defend integer default 0,
  p_reserve integer default 0, p_use_skill boolean default false,
  p_swap_to integer default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r public.shine_rooms%rowtype;
  s jsonb; me jsonb; foe jsonb; cards jsonb; foe_cards jsonb;
  unit jsonb; enemy_unit jsonb; spec public.shine_characters%rowtype;
  t integer; actor integer; active_idx integer; enemy_idx integer;
  avail integer; cost integer; cd integer; i integer; candidate integer;
  pierce integer := 0; bonus_damage integer := 0; extra_block integer := 0;
  extra_reserve integer := 0; enemy_block integer; effective_attack integer;
  dmg integer := 0; health integer; result_winner integer := null;
  mult numeric[] := array[0,1,2.4,4.2,6.4,9,12,15.4,20];
  message text; own_dead boolean; enemy_dead boolean;
begin
  if (select auth.uid()) is null then raise exception 'Masuk terlebih dahulu.'; end if;
  select * into r from public.shine_rooms where id=p_room_id for update;
  if not found or r.status <> 'playing' then raise exception 'Pertandingan tidak tersedia.'; end if;
  if p_expected_revision is distinct from r.revision then
    raise exception 'Keadaan pertandingan telah berubah, muat ulang.';
  end if;
  s := r.state;
  t := (s->>'turn')::integer;
  actor := (t-1)%2;
  if (actor=0 and r.host_id <> (select auth.uid())) or
     (actor=1 and r.guest_id <> (select auth.uid())) then
    raise exception 'Bukan giliran Anda.';
  end if;
  me := s->'teams'->actor;
  foe := s->'teams'->(1-actor);
  cards := me->'cards'; foe_cards := foe->'cards';
  active_idx := (me->>'active')::integer;
  enemy_idx := (foe->>'active')::integer;
  unit := cards->active_idx;
  enemy_unit := foe_cards->enemy_idx;
  select * into spec from public.shine_characters where id=unit->>'id';
  if (unit->>'hp')::integer <= 0 then raise exception 'Tokoh aktif tumbang.'; end if;

  if p_swap_to is not null then
    if p_attack <> 0 or p_defend <> 0 or p_reserve <> 0 or p_use_skill then
      raise exception 'Pergantian harus menjadi satu-satunya tindakan.';
    end if;
    if p_swap_to not between 0 and 2 or p_swap_to=active_idx or
       (cards->p_swap_to->>'hp')::integer <= 0 then
      raise exception 'Target pergantian tidak valid.';
    end if;
    me := jsonb_set(me,'{active}',to_jsonb(p_swap_to));
    me := jsonb_set(me,'{block}','0'::jsonb);
    foe := jsonb_set(foe,'{block}','0'::jsonb);
    message := 'Tim ' || case when actor=0 then 'A' else 'B' end ||
      ' berganti ke ' || (select name from public.shine_characters
      where id=cards->p_swap_to->>'id') || '. Giliran selesai.';
  else
    if p_attack is null or p_defend is null or p_reserve is null or
       p_attack < 0 or p_defend < 0 or p_reserve not between 0 and 4 then
      raise exception 'Nilai PA tidak valid.';
    end if;
    cost := case when p_use_skill then spec.skill_cost else 0 end;
    avail := least(8,least(t,4)+(me->>'reserve')::integer);
    if p_attack+p_defend+p_reserve+cost <> avail then
      raise exception 'Seluruh PA harus dialokasikan: tersedia %.',avail;
    end if;
    cd := (unit->>'cd')::integer;
    if p_use_skill and cd <> 0 then raise exception 'Skill masih cooldown.'; end if;
    if p_use_skill and spec.skill_kind in
      ('damage','pierce','recoil','conditional_damage','hybrid') and p_attack=0 then
      raise exception 'Skill ofensif memerlukan PA serang.';
    end if;
    if p_use_skill and spec.skill_kind='conditional_damage' and
       spec.skill_aux>0 and p_attack<spec.skill_aux then
      raise exception 'PA serang kurang untuk skill ini.';
    end if;
    if p_use_skill then
      case spec.skill_kind
        when 'damage' then bonus_damage := spec.skill_value;
        when 'recoil' then bonus_damage := spec.skill_value;
        when 'pierce' then pierce := spec.skill_value;
        when 'heal' then
          unit := jsonb_set(unit,'{hp}',to_jsonb(least(spec.hp,(unit->>'hp')::integer+spec.skill_value)));
        when 'heal_all' then
          for i in 0..2 loop
            if (cards->i->>'hp')::integer>0 then
              cards := jsonb_set(cards,array[i::text,'hp'],to_jsonb(
                least((cards->i->>'max_hp')::integer,
                  (cards->i->>'hp')::integer+spec.skill_value)));
            end if;
          end loop;
          unit := cards->active_idx;
        when 'shield' then extra_block := spec.skill_value;
        when 'reserve' then extra_reserve := spec.skill_value;
        when 'drain' then
          foe := jsonb_set(foe,'{reserve}',to_jsonb(
            greatest(0,(foe->>'reserve')::integer-spec.skill_value)));
        when 'hybrid' then
          bonus_damage := spec.skill_value; extra_block := spec.skill_aux;
        when 'conditional_damage' then
          if spec.skill_aux>0 or (foe->>'block')::integer=0 then
            bonus_damage := spec.skill_value;
          end if;
        else raise exception 'Jenis skill belum didukung.';
      end case;
    end if;
    enemy_block := (foe->>'block')::integer;
    effective_attack := greatest(0,p_attack-greatest(0,enemy_block-pierce));
    dmg := ceil(spec.attack*mult[effective_attack+1])::integer +
      case when effective_attack>0 then bonus_damage else 0 end;
    enemy_unit := jsonb_set(enemy_unit,'{hp}',to_jsonb(
      greatest(0,(enemy_unit->>'hp')::integer-dmg)));
    foe_cards := jsonb_set(foe_cards,array[enemy_idx::text],enemy_unit);
    if p_use_skill and spec.skill_kind='recoil' then
      unit := jsonb_set(unit,'{hp}',to_jsonb(
        greatest(0,(unit->>'hp')::integer-spec.skill_aux)));
    end if;
    cards := jsonb_set(cards,array[active_idx::text],unit);
    me := jsonb_set(me,'{block}',to_jsonb(least(8,p_defend+extra_block)));
    me := jsonb_set(me,'{reserve}',to_jsonb(least(4,p_reserve+extra_reserve)));
    foe := jsonb_set(foe,'{block}','0'::jsonb);
    message := 'Tim ' || case when actor=0 then 'A' else 'B' end ||
      ': '||p_attack||' serang, '||p_defend||' bertahan, '||p_reserve||
      ' cadangan. Damage '||dmg||'.'||
      case when p_use_skill then ' Skill '||spec.skill_name||' aktif.' else '' end;
  end if;

  -- CD berlaku untuk seluruh tim, termasuk kartu cadangan.
  for i in 0..2 loop
    unit := cards->i;
    if p_use_skill and p_swap_to is null and i=active_idx then
      cd := spec.skill_cooldown;
    else
      cd := greatest(0,(unit->>'cd')::integer-1);
    end if;
    cards := jsonb_set(cards,array[i::text,'cd'],to_jsonb(cd));
  end loop;
  me := jsonb_set(me,'{cards}',cards);
  foe := jsonb_set(foe,'{cards}',foe_cards);
  -- Prototipe: kartu paling awal yang masih hidup otomatis mengganti kartu KO.
  if (foe_cards->enemy_idx->>'hp')::integer <= 0 then
    for i in 0..2 loop
      if (foe_cards->i->>'hp')::integer > 0 then
        foe := jsonb_set(foe,'{active}',to_jsonb(i));
        exit;
      end if;
    end loop;
  end if;
  if (cards->active_idx->>'hp')::integer <= 0 then
    for i in 0..2 loop
      if (cards->i->>'hp')::integer > 0 then
        me := jsonb_set(me,'{active}',to_jsonb(i));
        exit;
      end if;
    end loop;
  end if;
  select bool_and((value->>'hp')::integer<=0) into own_dead
    from jsonb_array_elements(cards);
  select bool_and((value->>'hp')::integer<=0) into enemy_dead
    from jsonb_array_elements(foe_cards);
  if enemy_dead then result_winner := actor; end if;
  if own_dead then result_winner := 1-actor; end if;
  s := jsonb_build_object('turn',t+1,'winner',result_winner,
    'log',message,'teams',case when actor=0 then jsonb_build_array(me,foe)
                                 else jsonb_build_array(foe,me) end);
  update public.shine_rooms
    set state=s, revision=revision+1,
        status=case when result_winner is null then 'playing' else 'finished' end
    where id=p_room_id;
  return jsonb_build_object('state',s,'revision',r.revision+1);
end;
$$;

-- Restrict API execution (helpers stay inaccessible to clients).
revoke execute on function public.shine_validate_lineup(text[]) from public, anon, authenticated;
revoke execute on function public.shine_make_team(text[]) from public, anon, authenticated;
revoke execute on function public.shine_create_room(text[]) from public, anon;
revoke execute on function public.shine_join_room(text,text[]) from public, anon;
revoke execute on function public.shine_submit_action(uuid,integer,integer,integer,integer,boolean,integer) from public, anon;
grant execute on function public.shine_create_room(text[]) to authenticated;
grant execute on function public.shine_join_room(text,text[]) to authenticated;
grant execute on function public.shine_submit_action(uuid,integer,integer,integer,integer,boolean,integer) to authenticated;

-- Realtime perubahan room; RLS tetap membatasi ke dua anggota room.
do $$ begin
  if not exists (select 1 from pg_publication_tables
                 where pubname='supabase_realtime' and schemaname='public' and tablename='shine_rooms') then
    alter publication supabase_realtime add table public.shine_rooms;
  end if;
end $$;

-- Data 26 tokoh ditambahkan di bawah, berasal dari katalog draft.
insert into public.shine_characters (id,name,hp,attack,skill_name,skill_kind,skill_cost,skill_cooldown,skill_value,skill_aux) values
  ('alejandronavarro','Alejandro Navarro',500,27,'Serangan Beruntun','damage',2,2,15,0),
  ('arystanbeknurlanuly','Arystanbek Nurlanuly',580,24,'Benteng Kokoh','shield',2,3,2,0),
  ('baekseoyeon','Baek Seo-yeon',420,25,'Gangguan Ritme','drain',3,4,1,0),
  ('callummacgregor','Callum MacGregor',480,29,'Pukulan Penentu','damage',2,2,25,0),
  ('chahyunjae','Cha Hyun-jae',460,31,'Gerak Kilat','pierce',2,3,1,0),
  ('chaminhyuk','Cha Min-hyuk',520,30,'Momentum','damage',2,2,15,0),
  ('choinari','Choi Na-ri',400,24,'Semangat Baru','heal_all',3,4,15,0),
  ('fujiwaraaoi','Fujiwara Aoi',420,27,'Pengalih Perhatian','shield',2,3,1,0),
  ('hanseoah','Han Seo-ah',440,20,'Dukungan','heal',2,3,25,0),
  ('hanseoyul','Han Seo-yul',420,26,'Perhitungan Cermat','reserve',1,3,1,0),
  ('junghyunwoo','Jung Hyun-woo',540,26,'Pertahanan Balik','shield',2,3,1,0),
  ('kangjiwoo','Kang Ji-woo',460,29,'Langkah Gesit','shield',2,3,2,0),
  ('kavehshirazi','Kaveh Shirazi',500,28,'Adaptasi','damage',2,2,10,0),
  ('kimdasol','Kim Da-sol',440,25,'Jebakan Taktis','shield',2,2,1,0),
  ('kurokawaren','Kurokawa Ren',460,32,'Serangan Nekat','recoil',2,3,40,10),
  ('kwontaehyuk','Kwon Tae-hyuk',560,27,'Tekad Baja','shield',2,3,1,0),
  ('laylaalzahra','Layla Al-Zahra',420,24,'Perlindungan Rekan','shield',2,3,2,0),
  ('leejunseo','Lee Jun-seo',400,23,'Analisis','pierce',1,2,1,0),
  ('linzixuan','Lin Zixuan',480,28,'Titik Lemah','pierce',3,3,2,0),
  ('namseojun','Nam Seo-jun',500,26,'Formasi Bertahan','shield',2,3,2,0),
  ('ragnarsigurdsson','Ragnar Sigurdsson',600,28,'Daya Gempur','conditional_damage',3,3,30,3),
  ('suqinghuan','Su Qinghuan',400,26,'Kendali Tempo','drain',2,4,1,0),
  ('udomsakchanthavong','Udomsak Chanthavong',560,29,'Tekanan Bertubi','damage',2,3,20,0),
  ('xuwenjing','Xu Wenjing',400,22,'Pemulihan Tenang','heal',2,3,30,0),
  ('zaydalharith','Zayd al-Harith',520,27,'Keseimbangan','hybrid',2,2,10,1),
  ('zhangmingzhe','Zhang Mingzhe',440,30,'Strategi Tersembunyi','conditional_damage',2,2,20,0)
on conflict (id) do update set name=excluded.name, hp=excluded.hp,
 attack=excluded.attack, skill_name=excluded.skill_name, skill_kind=excluded.skill_kind,
 skill_cost=excluded.skill_cost, skill_cooldown=excluded.skill_cooldown,
 skill_value=excluded.skill_value, skill_aux=excluded.skill_aux;
