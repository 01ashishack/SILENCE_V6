-- Migration: Allow members to SELECT settings for libraries they belong to
-- Target: public.settings table
-- Reason: Member app needs to read settings (e.g. referral_settings) to gate features

CREATE POLICY "Members view library settings" ON public.settings
    FOR SELECT
    TO authenticated
    USING (
        library_id IN (
            SELECT library_id 
            FROM public.memberships 
            WHERE member_id = auth.uid()
        )
    );
