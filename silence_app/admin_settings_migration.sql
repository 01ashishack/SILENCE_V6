CREATE TABLE IF NOT EXISTS public.settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  library_id UUID REFERENCES public.libraries(id) ON DELETE CASCADE,
  scope TEXT NOT NULL,
  value JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (admin_id, library_id, scope)
);

ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read own settings" ON public.settings;
CREATE POLICY "Admins can read own settings"
ON public.settings
FOR SELECT
USING (
  auth.uid() = admin_id
  OR EXISTS (
    SELECT 1 FROM public.libraries
    WHERE libraries.id = settings.library_id
      AND libraries.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Admins can insert own settings" ON public.settings;
CREATE POLICY "Admins can insert own settings"
ON public.settings
FOR INSERT
WITH CHECK (
  auth.uid() = admin_id
  OR EXISTS (
    SELECT 1 FROM public.libraries
    WHERE libraries.id = settings.library_id
      AND libraries.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Admins can update own settings" ON public.settings;
CREATE POLICY "Admins can update own settings"
ON public.settings
FOR UPDATE
USING (
  auth.uid() = admin_id
  OR EXISTS (
    SELECT 1 FROM public.libraries
    WHERE libraries.id = settings.library_id
      AND libraries.owner_id = auth.uid()
  )
)
WITH CHECK (
  auth.uid() = admin_id
  OR EXISTS (
    SELECT 1 FROM public.libraries
    WHERE libraries.id = settings.library_id
      AND libraries.owner_id = auth.uid()
  )
);

CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'general',
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can read own notifications" ON public.notifications;
CREATE POLICY "Members can read own notifications"
ON public.notifications
FOR SELECT
USING (auth.uid() = member_id);

DROP POLICY IF EXISTS "Admins can create member notifications" ON public.notifications;
CREATE POLICY "Admins can create member notifications"
ON public.notifications
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.memberships
    WHERE memberships.member_id = notifications.member_id
      AND EXISTS (
        SELECT 1 FROM public.libraries
        WHERE libraries.id = memberships.library_id
          AND libraries.owner_id = auth.uid()
      )
  )
);

CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  performer_name TEXT,
  category TEXT NOT NULL DEFAULT 'settings',
  action_title TEXT NOT NULL,
  action_details TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read audit log" ON public.audit_log;
CREATE POLICY "Authenticated users can read audit log"
ON public.audit_log
FOR SELECT
USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Authenticated users can create audit log" ON public.audit_log;
CREATE POLICY "Authenticated users can create audit log"
ON public.audit_log
FOR INSERT
WITH CHECK (auth.uid() IS NOT NULL);
