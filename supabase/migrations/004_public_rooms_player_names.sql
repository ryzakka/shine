-- Shine v1.4.0 • PUBLIC / PRIVATE DIRECTORY & PLAYER DISPLAY NAMES
-- Requires 003_lobby_draft_reveal.sql AND previous Shine RPC/tables.
-- Apply on Supabase SQL Editor before deploying the new frontend.
BEGIN;

ALTER TABLE public.shine_rooms
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'private',
  ADD COLUMN IF NOT EXISTS room_title text NOT NULL DEFAULT 'Arena Shine',
  ADD COLUMN IF NOT EXISTS host_name text NOT NULL DEFAULT 'Pemain A',
  ADD COLUMN IF NOT EXISTS guest_name text;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
    WHERE conrelid='public.shine_rooms'::regclass AND conname='shine_visibility_check') THEN
    ALTER TABLE public.shine_rooms ADD CONSTRAINT shine_visibility_check
      CHECK (visibility IN ('public','private'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
    WHERE conrelid='public.shine_rooms'::regclass AND conname='shine_display_names_check') THEN
    ALTER TABLE public.shine_rooms ADD CONSTRAINT shine_display_names_check
      CHECK (char_length(host_name) BETWEEN 1 AND 24 AND
        (guest_name IS NULL OR char_length(guest_name) BETWEEN 1 AND 24) AND
        char_length(room_title) BETWEEN 1 AND 36);
  END IF;
END $$;

-- Old rooms are private by default; there is no accidental public migration.
CREATE INDEX IF NOT EXISTS shine_public_waiting_idx
  ON public.shine_rooms(created_at DESC)
  WHERE visibility='public' AND status='waiting' AND guest_id IS NULL;

-- Only the fields required for browsing are returned. No private room or
-- invitation code is exposed by this listing RPC.
CREATE OR REPLACE FUNCTION public.shine_list_public_rooms()
RETURNS TABLE(room_id uuid, room_title text, host_name text,
              created_at timestamptz, turn_seconds integer)
LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT r.id, r.room_title, r.host_name, r.created_at, r.turn_seconds
  FROM public.shine_rooms r
  WHERE (SELECT auth.uid()) IS NOT NULL
    AND r.visibility='public' AND r.status='waiting'
    AND r.guest_id IS NULL AND r.lobby_phase='gathering'
  ORDER BY r.created_at DESC LIMIT 50;
$function$;

CREATE OR REPLACE FUNCTION public.shine_create_room_v14(
  p_visibility text, p_room_title text, p_player_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_id uuid; v_code text; v_attempt integer;
  v_name text := btrim(coalesce(p_player_name,''));
  v_title text := btrim(coalesce(p_room_title,''));
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Masuk terlebih dahulu.'; END IF;
  IF p_visibility IS NULL OR p_visibility NOT IN ('public','private') THEN
    RAISE EXCEPTION 'Jenis ruang tidak valid.';
  END IF;
  IF char_length(v_name) NOT BETWEEN 2 AND 24 OR v_name ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'Nama pemain harus 2-24 karakter biasa.';
  END IF;
  IF v_title = '' THEN v_title := 'Arena ' || v_name; END IF;
  IF char_length(v_title) > 36 OR v_title ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'Nama ruang maksimal 36 karakter.';
  END IF;
  FOR v_attempt IN 1..12 LOOP
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    BEGIN
      INSERT INTO public.shine_rooms(code,host_id,host_cards,visibility,
                                   room_title,host_name,lobby_phase,host_ready)
      VALUES (v_code,(SELECT auth.uid()),ARRAY[]::text[],p_visibility,
              v_title,v_name,'gathering',false)
      RETURNING id INTO v_id;
      RETURN jsonb_build_object('id',v_id,'code',v_code);
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
  RAISE EXCEPTION 'Tidak dapat membuat kode ruang. Coba lagi.';
END;
$function$;

-- A private code may also be used for a public room, but its membership
-- always requires the correct code. The query locks the row to prevent races.
CREATE OR REPLACE FUNCTION public.shine_join_named_room_v14(
  p_code text, p_player_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r public.shine_rooms%rowtype;
  v_name text := btrim(coalesce(p_player_name,''));
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Masuk terlebih dahulu.'; END IF;
  IF char_length(v_name) NOT BETWEEN 2 AND 24 OR v_name ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'Nama pemain harus 2-24 karakter biasa.';
  END IF;
  SELECT * INTO r FROM public.shine_rooms
    WHERE code=upper(btrim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Kode ruang tidak ditemukan.'; END IF;
  IF r.host_id=(SELECT auth.uid()) THEN RAISE EXCEPTION 'Host tidak dapat menjadi tamu.'; END IF;
  IF r.status<>'waiting' OR r.guest_id IS NOT NULL OR r.lobby_phase<>'gathering' THEN
    RAISE EXCEPTION 'Ruang penuh atau tidak lagi menerima pemain.';
  END IF;
  UPDATE public.shine_rooms SET guest_id=(SELECT auth.uid()),
    guest_name=v_name,guest_cards=ARRAY[]::text[],guest_ready=false,
    host_ready=false,lobby_phase='draft',reveal_started_at=NULL,revision=revision+1
  WHERE id=r.id;
  RETURN jsonb_build_object('id',r.id,'code',r.code);
END;
$function$;

CREATE OR REPLACE FUNCTION public.shine_join_public_room_v14(
  p_room_id uuid, p_player_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r public.shine_rooms%rowtype;
  v_name text := btrim(coalesce(p_player_name,''));
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Masuk terlebih dahulu.'; END IF;
  IF char_length(v_name) NOT BETWEEN 2 AND 24 OR v_name ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'Nama pemain harus 2-24 karakter biasa.';
  END IF;
  SELECT * INTO r FROM public.shine_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR r.visibility<>'public' OR r.status<>'waiting'
    OR r.guest_id IS NOT NULL OR r.lobby_phase<>'gathering' THEN
    RAISE EXCEPTION 'Ruang publik sudah penuh atau tidak tersedia.';
  END IF;
  IF r.host_id=(SELECT auth.uid()) THEN
    RAISE EXCEPTION 'Tidak bisa masuk ke ruang milik sendiri.';
  END IF;
  UPDATE public.shine_rooms SET guest_id=(SELECT auth.uid()),
    guest_name=v_name,guest_cards=ARRAY[]::text[],guest_ready=false,
    host_ready=false,lobby_phase='draft',reveal_started_at=NULL,revision=revision+1
  WHERE id=r.id;
  RETURN jsonb_build_object('id',r.id,'code',r.code);
END;
$function$;

-- A guest who leaves must not leave their display name in the abandoned slot.
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
  UPDATE public.shine_rooms SET guest_id=NULL,guest_name=NULL,
    guest_cards=NULL,host_cards=ARRAY[]::text[],host_ready=false,
    guest_ready=false,lobby_phase='gathering',reveal_started_at=NULL,
    revision=revision+1 WHERE id=p_room_id;
END;
$function$;

-- Defense in depth for privacy: even if an earlier migration created a
-- permissive read policy, the restrictive guard still prevents listing
-- somebody else's private room by querying the table directly.
ALTER TABLE public.shine_rooms ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND tablename='shine_rooms'
        AND policyname='shine_members_read_v14') THEN
    EXECUTE $policy$CREATE POLICY shine_members_read_v14 ON public.shine_rooms
      FOR SELECT TO authenticated USING
      (host_id=(SELECT auth.uid()) OR guest_id=(SELECT auth.uid()))$policy$;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND tablename='shine_rooms'
        AND policyname='shine_privacy_guard_v14') THEN
    EXECUTE $policy$CREATE POLICY shine_privacy_guard_v14 ON public.shine_rooms
      AS RESTRICTIVE FOR SELECT TO authenticated USING
      (host_id=(SELECT auth.uid()) OR guest_id=(SELECT auth.uid()))$policy$;
  END IF;
END $$;

-- Do not grant public access to SECURITY DEFINER RPCs by default.
REVOKE ALL ON FUNCTION public.shine_list_public_rooms() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.shine_create_room_v14(text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.shine_join_named_room_v14(text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.shine_join_public_room_v14(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.shine_list_public_rooms() TO authenticated;
GRANT EXECUTE ON FUNCTION public.shine_create_room_v14(text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shine_join_named_room_v14(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shine_join_public_room_v14(uuid,text) TO authenticated;

COMMIT;
