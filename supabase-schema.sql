-- Fresh setup for Only Us. Run in Supabase SQL Editor on a NEW project.
-- Never expose the service-role/secret key in browser code.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text,
 is_admin boolean not null default false,
 is_premium boolean not null default false,
 premium_until timestamptz,
 couple_id uuid,
 created_at timestamptz not null default now()
);
create table if not exists public.couples (
 id uuid primary key default gen_random_uuid(),
 pairing_code text unique not null,
 user_one uuid not null references auth.users(id) on delete cascade,
 user_two uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 check (user_two is null or user_two <> user_one)
);
alter table public.profiles drop constraint if exists profiles_couple_id_fkey;
alter table public.profiles add constraint profiles_couple_id_fkey foreign key (couple_id) references public.couples(id) on delete set null;
create table if not exists public.payment_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 utr text not null, note text, amount_paise integer not null default 4900 check(amount_paise=4900),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.messages (
 id uuid primary key default gen_random_uuid(), couple_id uuid not null references public.couples(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 body text check(body is null or char_length(body) between 1 and 2000),
 media_path text, media_type text check(media_type is null or media_type in ('image','video','audio')),
 created_at timestamptz not null default now(),
 check ((body is not null and media_path is null and media_type is null) or (media_path is not null and media_type is not null))
);
create index if not exists messages_couple_created_idx on public.messages(couple_id, created_at);
create index if not exists payments_status_idx on public.payment_requests(status, created_at);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,email,is_admin) values(new.id,new.email,lower(coalesce(new.email,''))='singjaskaran68@gmail.com')
 on conflict(id) do update set email=excluded.email, is_admin=(lower(coalesce(excluded.email,''))='singjaskaran68@gmail.com' or public.profiles.is_admin);
 return new;
end; $$;
drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile after insert on auth.users for each row execute procedure public.handle_new_user();
-- Also promote the specified admin if the account already exists:
insert into public.profiles(id,email,is_admin)
select id,email,(lower(coalesce(email,''))='singjaskaran68@gmail.com') from auth.users
on conflict(id) do update set email=excluded.email, is_admin=(lower(coalesce(excluded.email,''))='singjaskaran68@gmail.com' or public.profiles.is_admin);
update public.profiles set is_admin=true where lower(email)='singjaskaran68@gmail.com';

alter table public.profiles enable row level security;
alter table public.couples enable row level security;
alter table public.payment_requests enable row level security;
alter table public.messages enable row level security;
revoke all on public.profiles, public.couples, public.payment_requests, public.messages from anon, authenticated;
grant select on public.profiles, public.couples, public.payment_requests, public.messages to authenticated;
grant insert on public.payment_requests, public.messages to authenticated;

create or replace function public.is_current_user_admin() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin); $$;
revoke all on function public.is_current_user_admin() from public, anon;
grant execute on function public.is_current_user_admin() to authenticated;

create policy "profiles self and admin read" on public.profiles for select to authenticated using(id=auth.uid() or public.is_current_user_admin());
create policy "couple members and admin read" on public.couples for select to authenticated using(user_one=auth.uid() or user_two=auth.uid() or public.is_current_user_admin());
create policy "own payments and admin read" on public.payment_requests for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users submit own pending payments" on public.payment_requests for insert to authenticated with check(user_id=auth.uid() and status='pending' and amount_paise=4900);
create policy "couple members and admin read messages" on public.messages for select to authenticated using(
 public.is_current_user_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.couple_id=messages.couple_id and p.is_premium and p.premium_until>now())
);
create policy "premium couple members send messages" on public.messages for insert to authenticated with check(
 user_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.couple_id=messages.couple_id and p.is_premium and p.premium_until>now()) and
 exists(select 1 from public.couples c where c.id=messages.couple_id and (c.user_one=auth.uid() or c.user_two=auth.uid()))
);

create or replace function public.create_couple_pairing() returns table(couple_id uuid, pairing_code text) language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_code text;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if exists(select 1 from public.profiles p where p.id=auth.uid() and p.couple_id is not null) then raise exception 'You are already paired'; end if;
 v_code := upper(substr(encode(gen_random_bytes(8),'hex'),1,10));
 insert into public.couples(pairing_code,user_one) values(v_code,auth.uid()) returning id into v_id;
 update public.profiles set couple_id=v_id where id=auth.uid();
 return query select v_id,v_code;
end; $$;
revoke all on function public.create_couple_pairing() from public, anon;
grant execute on function public.create_couple_pairing() to authenticated;

create or replace function public.join_couple_pairing(p_code text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_couple public.couples%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if exists(select 1 from public.profiles p where p.id=auth.uid() and p.couple_id is not null) then raise exception 'You are already paired'; end if;
 select * into v_couple from public.couples where pairing_code=upper(trim(p_code)) for update;
 if not found then raise exception 'Pairing code not found'; end if;
 if v_couple.user_two is not null then raise exception 'This pairing code has already been used'; end if;
 if v_couple.user_one=auth.uid() then raise exception 'You cannot join your own code'; end if;
 update public.couples set user_two=auth.uid() where id=v_couple.id and user_two is null;
 if not found then raise exception 'This pairing code has already been used'; end if;
 update public.profiles set couple_id=v_couple.id where id=auth.uid();
 return v_couple.id;
end; $$;
revoke all on function public.join_couple_pairing(text) from public, anon;
grant execute on function public.join_couple_pairing(text) to authenticated;

create or replace function public.admin_review_payment(p_payment_id uuid,p_user_id uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
declare v_status text;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin) then raise exception 'Admin permission required'; end if;
 select status into v_status from public.payment_requests where id=p_payment_id and user_id=p_user_id for update;
 if v_status is null then raise exception 'Payment request not found'; end if;
 if v_status<>'pending' then raise exception 'Already reviewed'; end if;
 update public.payment_requests set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now() where id=p_payment_id;
 if p_approve then update public.profiles set is_premium=true,premium_until=greatest(coalesce(premium_until,now()),now())+interval '30 days' where id=p_user_id; end if;
end; $$;
revoke all on function public.admin_review_payment(uuid,uuid,boolean) from public, anon;
grant execute on function public.admin_review_payment(uuid,uuid,boolean) to authenticated;

-- Private bucket for images, videos and audio. Access limited to couple members and admin.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('couple-media','couple-media',false,52428800,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','audio/webm','audio/ogg','audio/mp4','audio/mpeg','audio/wav']) on conflict(id) do update set public=false,file_size_limit=52428800,allowed_mime_types=excluded.allowed_mime_types;
create policy "Couple members and admin read media" on storage.objects for select to authenticated using(bucket_id='couple-media' and (public.is_current_user_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.couple_id::text=(storage.foldername(name))[1])));
create policy "Premium couple members upload media" on storage.objects for insert to authenticated with check(bucket_id='couple-media' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_premium and p.premium_until>now() and p.couple_id::text=(storage.foldername(name))[1]));
create policy "Owners or admin delete media" on storage.objects for delete to authenticated using(bucket_id='couple-media' and (owner_id=auth.uid()::text or public.is_current_user_admin()));

-- Enable Realtime for chat.
do $$ begin alter publication supabase_realtime add table public.messages; exception when duplicate_object then null; when undefined_object then raise notice 'Enable Realtime for public.messages in dashboard'; end $$;
