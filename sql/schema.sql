CREATE SCHEMA IF NOT EXISTS groupscholar_outreach_response_tracker;

CREATE TABLE IF NOT EXISTS groupscholar_outreach_response_tracker.outreach_logs (
    id BIGSERIAL PRIMARY KEY,
    scholar_id TEXT NOT NULL,
    channel TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL,
    responded_at TIMESTAMPTZ,
    response_type TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS outreach_logs_scholar_idx
    ON groupscholar_outreach_response_tracker.outreach_logs (scholar_id);

CREATE INDEX IF NOT EXISTS outreach_logs_channel_idx
    ON groupscholar_outreach_response_tracker.outreach_logs (channel);

CREATE INDEX IF NOT EXISTS outreach_logs_sent_idx
    ON groupscholar_outreach_response_tracker.outreach_logs (sent_at);

CREATE INDEX IF NOT EXISTS outreach_logs_responded_idx
    ON groupscholar_outreach_response_tracker.outreach_logs (responded_at);
