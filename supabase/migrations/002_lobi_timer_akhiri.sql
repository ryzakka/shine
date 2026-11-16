-- SHINE v0.3 — migrasi inkremental. Jalankan SETELAH 001_shine_mvp.sql.
-- Tidak menghapus pemain, tokoh, riwayat pertandingan, atau tabel lama.
-- Seluruh keputusan server melalui RPC otorisasi. Key service_role tidak diperlukan di aplikasi.

begin;

alter table public.shine_rooms
  add column if not exists guest_ready boolean not null default false,
  add column if not exists turn_seconds integer not null default 30,
  add column if not exists turn_deadline timestamptz,
  add column if not exists finished_reason text,
  add column if not exists ended_at timestamptz;

alter table public.shine_rooms drop constraint if exists shine_rooms_status_check;
alter table public.shine_rooms add constraint shine_rooms_status_check
  check (status in ('waiting','playing','finished','closed'));
alter table public.shine_rooms drop constraint if exists shine_rooms_turn_seconds_check;
alter table public.shine_rooms add constraint shine_rooms_turn_seconds_check
  check (turn_seconds in (20,30,45,60));

-- Pertandingan yang sudah aktif sebelum migrasi diberi tenggat baru.
update public.shine_rooms
set turn_deadline = clock_timestamp() + make_interval(secs => turn_seconds)
where status='playing' and turn_deadline is null;

-- Penggabungan pemain sekarang MEMBUKA LOBI, tidak memulai duel otomatis.
create or replace function public.shine_join_room(p_code text, p_cards text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.shine_rooms%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Masuk terlebih dahulu.'; end if;
  perform public.shine_validate_lineup(p_cards);
  select * into r from public.shine_rooms
    where code=upper(trim(p_code)) for update;
  if not found then raise exception 'Kode ruang tidak ditemukan.'; end if;
  if r.host_id=(select auth.uid()) then raise exception 'Host tidak dapat menjadi tamu.'; end if;
  if r.status<>'waiting' or r.guest_id is not null then
    raise exception 'Lobi sudah penuh atau tidak tersedia.';
  end if;
  update public.shine_rooms set guest_id=(select auth.uid()), guest_cards=p_cards,
    guest_ready=false, revision=revision+1 where id=r.id;
  return jsonb_build_object('id',r.id,'code',r.code);
end;
$$;

create or replace function public.shine_set_ready(p_room_id uuid,p_ready boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.shine_rooms%rowtype;
begin
  select * into r from public.shine_rooms where id=p_room_id for update;
  if not found or r.status <> 'waiting' then raise exception 'Lobi tidak tersedia.'; end if;
  if r.guest_id is distinct from (select auth.uid()) then
    raise exception 'Hanya pemain kedua yang mengatur status siap.';
  end if;
  update public.shine_rooms set guest_ready=coalesce(p_ready,false),
    revision=revision+1 where id=p_room_id;
end;
$$;

create or replace function public.shine_set_timer(p_room_id uuid,p_seconds integer)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.shine_rooms%rowtype;
begin
  if p_seconds is null or p_seconds not in (20,30,45,60) then
    raise exception 'Timer harus 20, 30, 45, atau 60 detik.';
  end if;
  select * into r from public.shine_rooms where id=p_room_id for update;
  if not found or r.status<>'waiting' then raise exception 'Lobi tidak tersedia.'; end if;
  if r.host_id is distinct from (select auth.uid()) then
    raise exception 'Hanya host yang menentukan durasi.';
  end if;
  update public.shine_rooms set turn_seconds=p_seconds,
    revision=revision+1 where id=p_room_id;
end;
$$;

create or replace function public.shine_start_room(p_room_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.shine_rooms%rowtype; s jsonb;
begin
  select * into r from public.shine_rooms where id=p_room_id for update;
  if not found or r.status <> 'waiting' then raise exception 'Lobi tidak tersedia.'; end if;
  if r.host_id is distinct from (select auth.uid()) then raise exception 'Hanya host yang memulai.'; end if;
  if r.guest_id is null or r.guest_cards is null or not r.guest_ready then
    raise exception 'Menunggu pemain kedua menekan Siap.';
  end if;
  s := jsonb_build_object('turn',1,'winner',null,'log','Pertandingan dimulai!',
    'teams',jsonb_build_array(public.shine_make_team(r.host_cards),
                               public.shine_make_team(r.guest_cards)));
  update public.shine_rooms set status='playing', state=s,
    turn_deadline=clock_timestamp()+make_interval(secs => r.turn_seconds),
    revision=revision+1 where id=p_room_id;
end;
$$;

-- Tamu boleh meninggalkan lobi. Pertandingan aktif harus memakai Menyerah.
create or replace function public.shine_leave_lobby(p_room_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.shine_rooms%rowtype;
begin
  select * into r from public.shine_rooms where id=p_room_id for update;
  if not found or r.status<>'waiting' then raise exception 'Hanya bisa keluar saat di lobi.'; end if;
  if r.guest_id is distinct from (select auth.uid()) then raise exception 'Hanya tamu yang dapat keluar lobi.'; end if;
  update public.shine_rooms set guest_id=null,guest_cards=null,guest_ready=false,
    revision=revision+1 where id=p_room_id;
end;
$$;

-- Mode: surrender (oleh salah satu pemain saat bermain), disband (host kapan saja).
create or replace function public.shine_end_room(p_room_id uuid,p_mode text)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.shine_rooms%rowtype; winner_side integer; ending text; s jsonb;
begin
  select * into r from public.shine_rooms where id=p_room_id for update;
  if not found then raise exception 'Ruang tidak ditemukan.'; end if;
  if (select auth.uid()) is distinct from r.host_id and
     (select auth.uid()) is distinct from r.guest_id then
    raise exception 'Anda bukan anggota ruang ini.';
  end if;
  if r.status not in ('waiting','playing') then raise exception 'Ruang sudah selesai.'; end if;
  s := r.state;
  if p_mode='disband' then
    if r.host_id is distinct from (select auth.uid()) then
      raise exception 'Hanya host yang dapat membubarkan ruang.';
    end if;
    ending := 'Dibubarkan oleh host';
    if s is not null then
      s := jsonb_set(jsonb_set(s,'{winner}','null'::jsonb),
        '{log}',to_jsonb('Host membubarkan pertandingan.'::text));
    end if;
    update public.shine_rooms set status='closed', state=s,finished_reason=ending,
      ended_at=clock_timestamp(),turn_deadline=null,revision=revision+1 where id=p_room_id;
  elsif p_mode='surrender' then
    if r.status<>'playing' then raise exception 'Menyerah hanya selama pertandingan.'; end if;
    winner_side := case when r.host_id=(select auth.uid()) then 1 else 0 end;
    ending := 'Menyerah';
    s := jsonb_set(jsonb_set(s,'{winner}',to_jsonb(winner_side)),
      '{log}',to_jsonb(('Tim '|| case when winner_side=0 then 'B' else 'A' end ||
      ' menyerah. Lawan menang.')::text));
    update public.shine_rooms set status='finished',state=s,finished_reason=ending,
      ended_at=clock_timestamp(),turn_deadline=null,revision=revision+1 where id=p_room_id;
  else raise exception 'Jenis pengakhiran tidak dikenal.';
  end if;
end;
$$;

-- Timer ditentukan jam database, bukan jam ponsel. Siapa pun anggota ruang boleh
-- meminta timeout diproses; satu permintaan diproses secara atomik.
create or replace function public.shine_expire_turn(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.shine_rooms%rowtype; s jsonb; actor integer; own_team jsonb;
        other_team jsonb; all_cards jsonb; unit jsonb; i integer; msg text;
begin
  select * into r from public.shine_rooms where id=p_room_id for update;
  if not found then raise exception 'Ruang tidak ditemukan.'; end if;
  if (select auth.uid()) is distinct from r.host_id and
     (select auth.uid()) is distinct from r.guest_id then
    raise exception 'Anda bukan anggota ruang ini.';
  end if;
  if r.status<>'playing' or r.turn_deadline is null or clock_timestamp()<r.turn_deadline then
    return jsonb_build_object('state',r.state,'revision',r.revision,'expired',false);
  end if;
  s:=r.state;
  actor:=((s->>'turn')::integer-1)%2;
  own_team:=s->'teams'->actor;
  other_team:=s->'teams'->(1-actor);
  all_cards:=own_team->'cards';
  for i in 0..2 loop
    unit:=all_cards->i;
    unit:=jsonb_set(unit,'{cd}',to_jsonb(greatest(0,(unit->>'cd')::integer-1)));
    all_cards:=jsonb_set(all_cards,array[i::text],unit);
  end loop;
  own_team:=jsonb_set(jsonb_set(own_team,'{cards}',all_cards),'{block}','0'::jsonb);
  other_team:=jsonb_set(other_team,'{block}','0'::jsonb);
  msg:='Waktu Tim '||case when actor=0 then 'A' else 'B' end||' habis. Giliran dilewati.';
  s:=jsonb_set(s,'{turn}',to_jsonb((s->>'turn')::integer+1));
  s:=jsonb_set(s,'{log}',to_jsonb(msg));
  s:=jsonb_set(s,'{teams}',case when actor=0 then jsonb_build_array(own_team,other_team)
                                   else jsonb_build_array(other_team,own_team) end);
  update public.shine_rooms set state=s,revision=revision+1,
    turn_deadline=clock_timestamp()+make_interval(secs => r.turn_seconds)
    where id=p_room_id;
  return jsonb_build_object('state',s,'revision',r.revision+1,'expired',true);
end;
$$;

-- Fungsi lama tetap dipakai sebagai engine dan tidak boleh dipanggil klien.
-- Migrasi ini dimaksudkan untuk instalasi 001 yang sudah ada.
do $$ begin
  if to_regprocedure('public.shine_submit_action_core(uuid,integer,integer,integer,integer,boolean,integer)') is null then
    execute 'alter function public.shine_submit_action(uuid,integer,integer,integer,integer,boolean,integer) rename to shine_submit_action_core';
  end if;
end $$;

create or replace function public.shine_submit_action(
  p_room_id uuid,p_expected_revision integer,
  p_attack integer default 0,p_defend integer default 0,p_reserve integer default 0,
  p_use_skill boolean default false,p_swap_to integer default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.shine_rooms%rowtype; answer jsonb;
begin
  select * into r from public.shine_rooms where id=p_room_id for update;
  if not found or r.status <> 'playing' then raise exception 'Pertandingan tidak tersedia.'; end if;
  if p_expected_revision is distinct from r.revision then
    raise exception 'Giliran berubah. Perbarui arena.';
  end if;
  -- Permintaan lewat waktu tidak boleh diterima walaupun perangkat memanipulasi timer.
  if r.turn_deadline is not null and clock_timestamp() >= r.turn_deadline then
    return public.shine_expire_turn(p_room_id);
  end if;
  answer:=public.shine_submit_action_core(p_room_id,p_expected_revision,
    p_attack,p_defend,p_reserve,p_use_skill,p_swap_to);
  update public.shine_rooms set
    turn_deadline=case when status='playing'
      then clock_timestamp()+make_interval(secs => turn_seconds) else null end,
    ended_at=case when status='finished' then clock_timestamp() else ended_at end,
    finished_reason=case when status='finished' then 'KO' else finished_reason end
    where id=p_room_id;
  return answer;
end;
$$;

-- RLS tetap read-only; seluruh mutasi memakai RPC yang memvalidasi auth.uid().
revoke execute on function public.shine_submit_action_core(uuid,integer,integer,integer,integer,boolean,integer) from public,anon,authenticated;
revoke execute on function public.shine_join_room(text,text[]) from public,anon;
revoke execute on function public.shine_start_room(uuid) from public,anon;
revoke execute on function public.shine_set_ready(uuid,boolean) from public,anon;
revoke execute on function public.shine_set_timer(uuid,integer) from public,anon;
revoke execute on function public.shine_leave_lobby(uuid) from public,anon;
revoke execute on function public.shine_end_room(uuid,text) from public,anon;
revoke execute on function public.shine_expire_turn(uuid) from public,anon;
revoke execute on function public.shine_submit_action(uuid,integer,integer,integer,integer,boolean,integer) from public,anon;
grant execute on function public.shine_start_room(uuid) to authenticated;
grant execute on function public.shine_set_ready(uuid,boolean) to authenticated;
grant execute on function public.shine_set_timer(uuid,integer) to authenticated;
grant execute on function public.shine_leave_lobby(uuid) to authenticated;
grant execute on function public.shine_end_room(uuid,text) to authenticated;
grant execute on function public.shine_expire_turn(uuid) to authenticated;
grant execute on function public.shine_submit_action(uuid,integer,integer,integer,integer,boolean,integer) to authenticated;

commit;
