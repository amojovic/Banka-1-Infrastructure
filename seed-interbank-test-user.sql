-- =============================================================================
-- Banka 1 — cross-bank test korisnik "Banka1 Interbank" (C-100)
-- Pandan Banka-2 korisniku C-8. Sve u jednoj bazi `db` (public schema).
-- Idempotentno: bezbedno za ponovno pokretanje.
--
-- Login:   banka1.interbank@banka.com / admin123
-- Klijent: id=100, role CLIENT_TRADING (+ CLIENT_OTC_TRADE permisija)
-- Racuni:  RSD 1110009900000000111 (5.000.000), USD ...411 (100.000), EUR ...211 (50.000)
-- Portfolio (javno za OTC): AAPL(1) MSFT(2) TSLA(5) — po 50 javnih
--
-- Lozinka (:hash) se prosledjuje preko psql -v hash=... (argon2id, generisan
-- istom funkcijom kao user-service platform.HashPassword).
-- =============================================================================
BEGIN;

-- 1) Klijent C-100 -----------------------------------------------------------
INSERT INTO clients (id, ime, prezime, datum_rodjenja, pol, email, broj_telefona, adresa,
                     password, role, aktivan, version, deleted)
VALUES (100, 'Banka1', 'Interbank', 631152000000, 'M', 'banka1.interbank@banka.com',
        '+381600000100', 'Bulevar Interbank 1, Beograd',
        :'hash', 'CLIENT_TRADING', true, 0, false)
ON CONFLICT (id) DO UPDATE SET
    email     = EXCLUDED.email,
    password  = EXCLUDED.password,
    role      = EXCLUDED.role,
    ime       = EXCLUDED.ime,
    prezime   = EXCLUDED.prezime,
    aktivan   = true,
    deleted   = false,
    updated_at = now();

-- BIGSERIAL drzimo iznad pinned id=100 da buduci INSERT-i ne kolidiraju
SELECT setval(pg_get_serial_sequence('clients','id'),
              GREATEST((SELECT max(id) FROM clients), 100));

-- 2) Permisije (CLIENT_OTC_TRADE je kljucna za OTC; ostalo za trgovinu/racune) -
INSERT INTO client_permissions (client_id, permission) VALUES
    (100, 'CLIENT_OTC_TRADE'),
    (100, 'CLIENT_SECURITIES_TRADE'),
    (100, 'CLIENT_ACCOUNT_ACCESS')
ON CONFLICT DO NOTHING;

-- 3) Racuni (vlasnik=100; currency_id preko oznake) --------------------------
-- RSD tekuci — 5.000.000
INSERT INTO account_table (
    version, account_type, broj_racuna, ime_vlasnika_racuna, prezime_vlasnika_racuna,
    email, username, naziv_racuna, vlasnik, zaposlen, stanje, raspolozivo_stanje,
    datum_i_vreme_kreiranja, datum_isteka, currency_id, status,
    dnevni_limit, mesecni_limit, dnevna_potrosnja, mesecna_potrosnja,
    company_id, account_concrete, odrzavanje_racuna, account_ownership_type)
SELECT 0, 'CHECKING', '1110009900000000111', 'Banka1', 'Interbank',
    'banka1.interbank@banka.com', 'banka1.interbank', 'Tekuci racun RSD', 100, 1,
    5000000.00, 5000000.00, NOW(), '2031-12-31', c.id, 'ACTIVE',
    5000000.00, 50000000.00, 0.00, 0.00, NULL, 'STANDARDNI', 255.00, NULL
FROM currency_table c WHERE c.oznaka='RSD'
ON CONFLICT (broj_racuna) DO NOTHING;

-- USD devizni — 100.000
INSERT INTO account_table (
    version, account_type, broj_racuna, ime_vlasnika_racuna, prezime_vlasnika_racuna,
    email, username, naziv_racuna, vlasnik, zaposlen, stanje, raspolozivo_stanje,
    datum_i_vreme_kreiranja, datum_isteka, currency_id, status,
    dnevni_limit, mesecni_limit, dnevna_potrosnja, mesecna_potrosnja,
    company_id, account_concrete, odrzavanje_racuna, account_ownership_type)
SELECT 0, 'FX', '1110009900000000411', 'Banka1', 'Interbank',
    NULL, NULL, 'Devizni racun USD', 100, 1,
    100000.00, 100000.00, NOW(), '2031-12-31', c.id, 'ACTIVE',
    100000.00, 1000000.00, 0.00, 0.00, NULL, NULL, NULL, 'PERSONAL'
FROM currency_table c WHERE c.oznaka='USD'
ON CONFLICT (broj_racuna) DO NOTHING;

-- EUR devizni — 50.000
INSERT INTO account_table (
    version, account_type, broj_racuna, ime_vlasnika_racuna, prezime_vlasnika_racuna,
    email, username, naziv_racuna, vlasnik, zaposlen, stanje, raspolozivo_stanje,
    datum_i_vreme_kreiranja, datum_isteka, currency_id, status,
    dnevni_limit, mesecni_limit, dnevna_potrosnja, mesecna_potrosnja,
    company_id, account_concrete, odrzavanje_racuna, account_ownership_type)
SELECT 0, 'FX', '1110009900000000211', 'Banka1', 'Interbank',
    NULL, NULL, 'Devizni racun EUR', 100, 1,
    50000.00, 50000.00, NOW(), '2031-12-31', c.id, 'ACTIVE',
    50000.00, 500000.00, 0.00, 0.00, NULL, NULL, NULL, 'PERSONAL'
FROM currency_table c WHERE c.oznaka='EUR'
ON CONFLICT (broj_racuna) DO NOTHING;

-- 4) Portfolio — AAPL(1) MSFT(2) TSLA(5), po 50 javnih za OTC prodaju --------
INSERT INTO portfolio (user_id, listing_id, listing_type, quantity, average_purchase_price,
                       is_public, public_quantity, last_modified, reserved_quantity)
SELECT 100, 1, 'STOCK', 50, 175.0000, true, 50, CURRENT_TIMESTAMP, 0
WHERE NOT EXISTS (SELECT 1 FROM portfolio WHERE user_id=100 AND listing_id=1);

INSERT INTO portfolio (user_id, listing_id, listing_type, quantity, average_purchase_price,
                       is_public, public_quantity, last_modified, reserved_quantity)
SELECT 100, 2, 'STOCK', 50, 415.0000, true, 50, CURRENT_TIMESTAMP, 0
WHERE NOT EXISTS (SELECT 1 FROM portfolio WHERE user_id=100 AND listing_id=2);

INSERT INTO portfolio (user_id, listing_id, listing_type, quantity, average_purchase_price,
                       is_public, public_quantity, last_modified, reserved_quantity)
SELECT 100, 5, 'STOCK', 50, 245.0000, true, 50, CURRENT_TIMESTAMP, 0
WHERE NOT EXISTS (SELECT 1 FROM portfolio WHERE user_id=100 AND listing_id=5);

COMMIT;
