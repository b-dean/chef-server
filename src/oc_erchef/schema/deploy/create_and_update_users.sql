-- Deploy enterprise_chef:create_and_update_users to pg
-- Inserts a sentinel value into the public_key field of a user table.
-- Ensures keys table is the only source of truth for public_key

BEGIN;

DROP FUNCTION If EXISTS add_user(character,character,text,text,text,integer,text,text,password_hash_type,character,timestamp without time zone,timestamp without time zone,text,boolean,text,boolean);

CREATE OR REPLACE FUNCTION add_user(p_id users.id%TYPE,
                                    p_authz_id users.authz_id%TYPE,
                                    p_username users.username%TYPE,
                                    p_email users.email%TYPE,
                                    p_public_key users.public_key%TYPE,
                                    p_pubkey_version users.pubkey_version%TYPE,
                                    p_hashed_password users.hashed_password%TYPE,
                                    p_salt users.salt%TYPE,
                                    p_hash_type users.hash_type%TYPE,
                                    p_last_updated_by users.last_updated_by%TYPE,
                                    p_created_at users.created_at%TYPE,
                                    p_updated_at users.updated_at%TYPE,
                                    p_external_authentication_uid users.external_authentication_uid%TYPE,
                                    p_recovery_authentication_enabled users.recovery_authentication_enabled%TYPE,
                                    p_serialized_object users.serialized_object%TYPE,
                                    p_admin users.admin%TYPE) RETURNS void AS $$
  BEGIN
    INSERT INTO users
      (id, authz_id, username, email, public_key, hashed_password, salt, hash_type,
       last_updated_by, created_at, updated_at, external_authentication_uid,
       recovery_authentication_enabled, serialized_object, admin,
       pubkey_version)
    VALUES (p_id, p_authz_id, p_username, p_email, 'thisisnotakey',
       p_hashed_password, p_salt, p_hash_type, p_last_updated_by, p_created_at, p_updated_at,
       p_external_authentication_uid, p_recovery_authentication_enabled,
       p_serialized_object, p_admin, p_pubkey_version);
    IF p_public_key != 'thisisnotakey' THEN
      INSERT INTO keys
        (id, key_name, public_key, key_version, created_at,  expires_at)
      VALUES
         (p_id, 'default', p_public_key, p_pubkey_version, now(), 'infinity'::timestamp);
    END IF;
  END
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS update_user(integer,text,text,text,password_hash_type,text,text,boolean,text,text,character,timestamp without time zone,boolean,character);

CREATE OR REPLACE FUNCTION update_user(p_pubkey_version users.pubkey_version%TYPE,
                                       p_public_key users.public_key%TYPE,
                                       p_hashed_password users.hashed_password%TYPE,
                                       p_salt users.salt%TYPE,
                                       p_hash_type users.hash_type%TYPE,
                                       p_serialized_object users.serialized_object%TYPE,
                                       p_external_authentication_uid users.external_authentication_uid%TYPE,
                                       p_recovery_authentication_enabled users.recovery_authentication_enabled%TYPE,
                                       p_email users.email%TYPE,
                                       p_username users.username%TYPE,
                                       p_last_updated_by users.last_updated_by%TYPE,
                                       p_updated_at users.updated_at%TYPE,
                                       p_admin users.admin%TYPE,
                                       p_id character(32)) RETURNS void AS $update_user$
    BEGIN
    IF p_public_key != 'thisisnotakey' THEN
      IF p_public_key IS NOT NULL THEN
        UPDATE keys SET public_key = p_public_key,
                        key_version = p_pubkey_version,
                        expires_at = 'infinity'::timestamp
        WHERE id = p_id AND key_name = 'default';
       INSERT INTO keys (id, key_name, public_key, key_version, created_at, expires_at)
         SELECT p_id, 'default', p_public_key, p_pubkey_version, now(), 'infinity'::timestamp
         WHERE NOT EXISTS (SELECT 1 FROM keys WHERE id = p_id AND key_name = 'default');
      ELSE
       DELETE FROM keys WHERE id = p_id AND key_name = 'default';
      END IF;
    END IF;
    UPDATE users SET
      public_key = 'thisisnotakey',
      hashed_password = p_hashed_password,
      salt = p_salt,
      hash_type = p_hash_type,
      last_updated_by = p_last_updated_by,
      updated_at = p_updated_at,
      external_authentication_uid = p_external_authentication_uid,
      recovery_authentication_enabled = p_recovery_authentication_enabled,
      serialized_object = p_serialized_object,
      admin = p_admin,
      pubkey_version = p_pubkey_version
    WHERE id = p_id;
   END
$update_user$ LANGUAGE plpgsql;

COMMIT;
