-- Shine v1.3: bergabung -> memilih tim bersama -> reveal -> arena.
-- JALANKAN SETELAH fungsi-fungsi Shine yang ada (01/02 atau SQL Supabase aktif).
-- Tidak mengubah pertandingan yang sudah dalam status 'playing'.
BEGIN;

ALTER TABLE public.shine_rooms
  ADD COLUMN IF NOT EXISTS lobby_phase text NOT NULL DEFAULT 'gathering'
    CHECK (lobby_phase IN ('gathering', 'draft', 'reveal')),
  ADD COLUMN IF NOT EXISTS host_ready boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reveal_started_at timestamptz;

-- Ruang versi lama yang masih menunggu perlu melalui pemilihan tim ulang.
UPDATE public.shine_rooms SET
  lobby_phase = CASE WHEN guest_id IS NULL THEN 'gathering' ELSE 'draft' END,
  host_ready = false,
  guest_ready = false,
  reveal_started_at = NULL
WHERE status = 'waiting';

CREATE OR REPLACE FUNCTION public.shine_create_room(p_cards text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_id uuid; v_code text; v_attempt integer;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Masuk terlebih dahulu.'; END IF;
  -- Mendukung pemanggil lama, tetapi pilihan final baru dilakukan saat kedua pemain hadir.
  IF coalesce(cardinality(p_cards), 0) > 0 THEN
    PERFORM public.shine_validate_lineup(p_cards);
  END IF;
  FOR v_attempt IN 1..12 LOOP
    v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
    BEGIN
      INSERT INTO public.shine_rooms(code,host_id,host_cards,host_ready,lobby_phase)
      VALUES(v_code,(SELECT auth.uid()),coalesce(p_cards,ARRAY[]::text[]),false,'gathering')
      RETURNING id INTO v_id;
      RETURN jsonb_build_object('id',v_id,'code',v_code);
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
  RAISE EXCEPTION 'Tidak dapat membuat kode ruang. Coba lagi.';
END;
$function$;

CREATE OR REPLACE FUNCTION public.shine_join_room(p_code text, p_cards text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r public.shine_rooms%rowtype;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Masuk terlebih dahulu.'; END IF;
  IF coalesce(cardinality(p_cards), 0) > 0 THEN
    PERFORM public.shine_validate_lineup(p_cards);
  END IF;
  SELECT * INTO r FROM public.shine_rooms
   WHERE code=upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Kode ruang tidak ditemukan.'; END IF;
  IF r.host_id=(SELECT auth.uid()) THEN RAISE EXCEPTION 'Host tidak dapat menjadi tamu.'; END IF;
  IF r.status<>'waiting' OR r.guest_id IS NOT NULL THEN
    RAISE EXCEPTION 'Lobi sudah penuh atau tidak tersedia.';
  END IF;
  UPDATE public.shine_rooms SET
    guest_id=(SELECT auth.uid()), guest_cards=coalesce(p_cards,ARRAY[]::text[]),
    guest_ready=false, host_ready=false, lobby_phase='draft', reveal_started_at=NULL,
    revision=revision+1
  WHERE id=r.id;
  RETURN jsonb_build_object('id',r.id,'code',r.code);
END;
$function$;

CREATE OR REPLACE FUNCTION public.shine_submit_lineup(p_room_id uuid, p_cards text[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r public.shine_rooms%rowtype; v_host_ready boolean; v_guest_ready boolean;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Masuk terlebih dahulu.'; END IF;
  PERFORM public.shine_validate_lineup(p_cards);
  SELECT * INTO r FROM public.shine_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR r.status<>'waiting' OR r.guest_id IS NULL
    OR r.lobby_phase<>'draft' THEN
    RAISE EXCEPTION 'Pemilihan kartu belum tersedia atau telah berakhir.';
  END IF;
  v_host_ready := r.host_ready;
  v_guest_ready := r.guest_ready;
  IF r.host_id=(SELECT auth.uid()) THEN
    IF r.host_ready THEN RAISE EXCEPTION 'Pilihan Tim A telah dikunci.'; END IF;
    UPDATE public.shine_rooms SET host_cards=p_cards,host_ready=true,revision=revision+1
      WHERE id=p_room_id;
    v_host_ready := true;
  ELSIF r.guest_id=(SELECT auth.uid()) THEN
    IF r.guest_ready THEN RAISE EXCEPTION 'Pilihan Tim B telah dikunci.'; END IF;
    UPDATE public.shine_rooms SET guest_cards=p_cards,guest_ready=true,revision=revision+1
      WHERE id=p_room_id;
    v_guest_ready := true;
  ELSE
    RAISE EXCEPTION 'Anda bukan peserta ruang ini.';
  END IF;
  IF v_host_ready AND v_guest_ready THEN
    UPDATE public.shine_rooms SET lobby_phase='reveal',
      reveal_started_at=clock_timestamp(),revision=revision+1 WHERE id=p_room_id;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.shine_start_room(p_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r public.shine_rooms%rowtype; s jsonb;
BEGIN
  SELECT * INTO r FROM public.shine_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ruang tidak ditemukan.'; END IF;
  IF r.host_id IS DISTINCT FROM (SELECT auth.uid()) AND
     r.guest_id IS DISTINCT FROM (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Anda bukan peserta ruang ini.';
  END IF;
  -- Idempoten: kedua perangkat boleh mencoba mengawali pertarungan.
  IF r.status='playing' THEN RETURN; END IF;
  IF r.status<>'waiting' OR r.guest_id IS NULL OR
     r.lobby_phase<>'reveal' OR NOT r.host_ready OR NOT r.guest_ready OR
     r.reveal_started_at IS NULL THEN
    RAISE EXCEPTION 'Menunggu pemilihan kedua tim dan pengungkapan.';
  END IF;
  IF clock_timestamp() < r.reveal_started_at + interval '8 seconds' THEN
    RAISE EXCEPTION 'Pengungkapan kartu sedang berlangsung.';
  END IF;
  PERFORM public.shine_validate_lineup(r.host_cards);
  PERFORM public.shine_validate_lineup(r.guest_cards);
  s:=jsonb_build_object('turn',1,'winner',null,'log','Pertandingan dimulai!',
      'teams',jsonb_build_array(public.shine_make_team(r.host_cards),
                                public.shine_make_team(r.guest_cards)));
  UPDATE public.shine_rooms SET status='playing',state=s,
    turn_deadline=clock_timestamp()+make_interval(secs=>r.turn_seconds),
    revision=revision+1 WHERE id=p_room_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.shine_leave_lobby(p_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r public.shine_rooms%rowtype;
BEGIN
  SELECT * INTO r FROM public.shine_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR r.status<>'waiting' THEN
    RAISE EXCEPTION 'Hanya bisa keluar saat di lobi.';
  END IF;
  IF r.guest_id IS DISTINCT FROM (SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Hanya tamu yang dapat keluar lobi.';
  END IF;
  IF r.lobby_phase='reveal' THEN
    RAISE EXCEPTION 'Pengungkapan sedang berlangsung.';
  END IF;
  UPDATE public.shine_rooms SET guest_id=NULL, guest_cards=NULL,
    host_cards=ARRAY[]::text[], host_ready=false, guest_ready=false,
    lobby_phase='gathering',reveal_started_at=NULL,revision=revision+1
  WHERE id=p_room_id;
END;
$function$;

-- Mencegah panggilan dari klien langsung ke mesin inti yang melewati deadline.
REVOKE EXECUTE ON FUNCTION public.shine_submit_action_core(
  uuid,integer,integer,integer,integer,boolean,integer)
FROM PUBLIC, anon, authenticated;
-- Endpoint siap lama tidak digunakan, dan bisa membuat false-ready tanpa kartu.
REVOKE EXECUTE ON FUNCTION public.shine_set_ready(uuid,boolean)
FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.shine_submit_lineup(uuid,text[])
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.shine_submit_lineup(uuid,text[]) TO authenticated;
COMMIT;
