-- Удаление существующих таблиц
DROP TABLE IF EXISTS audit_log CASCADE;
DROP TABLE IF EXISTS message_views CASCADE;
DROP TABLE IF EXISTS conversation_last_messages CASCADE;
DROP TABLE IF EXISTS messages CASCADE;
DROP TABLE IF EXISTS conversation_members CASCADE;
DROP TABLE IF EXISTS files CASCADE;
DROP TABLE IF EXISTS contacts CASCADE;
DROP TABLE IF EXISTS conversations CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- =============================================
-- 1. ТАБЛИЦА ПОЛЬЗОВАТЕЛЕЙ
-- =============================================
CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    avatar_url VARCHAR(500),
    status VARCHAR(50) DEFAULT 'offline',
    last_seen TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    is_verified BOOLEAN DEFAULT FALSE,
    timezone VARCHAR(50) DEFAULT 'UTC',
    bio TEXT,
    date_of_birth DATE,
    
    -- Ограничения
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT uq_users_phone UNIQUE (phone),
    
    CONSTRAINT chk_status CHECK (status IN ('online', 'offline', 'away', 'busy', 'invisible')),
    CONSTRAINT chk_username_length CHECK (LENGTH(username) >= 3 AND LENGTH(username) <= 50),
    CONSTRAINT chk_username_format CHECK (username ~ '^[a-zA-Z0-9_.-]+$'),
    CONSTRAINT chk_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_phone_format CHECK (phone IS NULL OR phone ~ '^\+?[1-9]\d{1,14}$'),
    CONSTRAINT chk_age CHECK (date_of_birth IS NULL OR date_of_birth <= CURRENT_DATE - INTERVAL '13 years')
);

-- =============================================
-- 2. ТАБЛИЦА КОНТАКТОВ
-- =============================================
CREATE TABLE contacts (
    contact_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    contact_user_id BIGINT NOT NULL,
    nickname VARCHAR(50),
    is_favorite BOOLEAN DEFAULT FALSE,
    is_blocked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT uq_user_contact UNIQUE(user_id, contact_user_id),
    CONSTRAINT fk_contacts_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_contacts_contact_user FOREIGN KEY (contact_user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_not_self_contact CHECK (user_id != contact_user_id)
);

-- =============================================
-- 3. ТАБЛИЦА ДИАЛОГОВ
-- =============================================
CREATE TABLE conversations (
    conversation_id BIGSERIAL PRIMARY KEY,
    conversation_type VARCHAR(20) NOT NULL,
    title VARCHAR(100),
    description TEXT,
    avatar_url VARCHAR(500),
    created_by BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    is_private BOOLEAN DEFAULT FALSE,
    max_members INTEGER DEFAULT 1000,
    metadata JSONB DEFAULT '{}',
    
    CONSTRAINT chk_conversation_type CHECK (conversation_type IN ('private', 'group', 'channel')),
    CONSTRAINT chk_max_members CHECK (max_members > 0 AND max_members <= 100000),
    CONSTRAINT fk_conversations_created_by FOREIGN KEY (created_by) REFERENCES users(user_id) ON DELETE SET NULL
);

-- =============================================
-- 4. ТАБЛИЦА УЧАСТНИКОВ ДИАЛОГОВ
-- =============================================
CREATE TABLE conversation_members (
    member_id BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    role VARCHAR(20) DEFAULT 'member',
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    left_at TIMESTAMP WITH TIME ZONE,
    is_muted BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    notification_settings JSONB DEFAULT '{"sound": true, "desktop": true, "mobile": true, "mentions": true}'::jsonb,
    custom_title VARCHAR(100),
    permissions JSONB DEFAULT '{"send_messages": true, "send_media": true, "add_members": false, "remove_members": false, "change_info": false}'::jsonb,
    
    CONSTRAINT uq_conversation_member UNIQUE(conversation_id, user_id),
    CONSTRAINT fk_conversation_members_conversation FOREIGN KEY (conversation_id) 
        REFERENCES conversations(conversation_id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_members_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_role CHECK (role IN ('owner', 'admin', 'moderator', 'member', 'readonly', 'banned')),
    CONSTRAINT chk_left_after_joined CHECK (left_at IS NULL OR left_at > joined_at)
);

-- =============================================
-- 5. ТАБЛИЦА ФАЙЛОВ
-- =============================================
CREATE TABLE files (
    file_id BIGSERIAL PRIMARY KEY,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL UNIQUE,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100),
    uploader_id BIGINT NOT NULL,
    upload_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_encrypted BOOLEAN DEFAULT FALSE,
    encryption_key VARCHAR(500),
    md5_hash VARCHAR(32),
    sha256_hash VARCHAR(64),
    width INTEGER,
    height INTEGER,
    duration INTEGER,
    thumbnail_path VARCHAR(500),
    
    CONSTRAINT fk_files_uploader FOREIGN KEY (uploader_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_file_size_positive CHECK (file_size > 0),
    CONSTRAINT chk_file_size_limit CHECK (file_size <= 100 * 1024 * 1024),
    CONSTRAINT chk_dimensions CHECK (
        (width IS NULL AND height IS NULL) OR 
        (width > 0 AND height > 0 AND width <= 10000 AND height <= 10000)
    )
);

-- =============================================
-- 6. ТАБЛИЦА СООБЩЕНИЙ
-- =============================================
CREATE TABLE messages (
    message_id BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL,
    sender_id BIGINT NOT NULL,
    message_type VARCHAR(20) NOT NULL,
    content TEXT,
    file_id BIGINT,
    parent_message_id BIGINT,
    sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    edited_at TIMESTAMP WITH TIME ZONE,
    is_edited BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by BIGINT,
    forward_from_message_id BIGINT,
    forward_from_conversation_id BIGINT,
    reply_markup JSONB,
    entities JSONB,
    search_vector tsvector GENERATED ALWAYS AS (
        to_tsvector('english', COALESCE(content, ''))
    ) STORED,
    
    CONSTRAINT fk_messages_conversation FOREIGN KEY (conversation_id) 
        REFERENCES conversations(conversation_id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) 
        REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_file FOREIGN KEY (file_id) 
        REFERENCES files(file_id) ON DELETE SET NULL,
    CONSTRAINT fk_messages_parent FOREIGN KEY (parent_message_id) 
        REFERENCES messages(message_id) ON DELETE SET NULL,
    CONSTRAINT fk_messages_deleted_by FOREIGN KEY (deleted_by) 
        REFERENCES users(user_id) ON DELETE SET NULL,
    
    CONSTRAINT chk_message_type CHECK (message_type IN (
        'text', 'image', 'video', 'audio', 'file', 'sticker', 
        'voice', 'video_note', 'poll', 'location', 'contact', 
        'system', 'service'
    )),
    CONSTRAINT chk_content_or_file CHECK (content IS NOT NULL OR file_id IS NOT NULL),
    CONSTRAINT chk_edited_after_sent CHECK (edited_at IS NULL OR edited_at >= sent_at),
    CONSTRAINT chk_deleted_after_sent CHECK (deleted_at IS NULL OR deleted_at >= sent_at),
    CONSTRAINT chk_not_self_reply CHECK (parent_message_id IS NULL OR parent_message_id != message_id)
);

-- =============================================
-- 7. ТАБЛИЦА ПРОСМОТРОВ СООБЩЕНИЙ
-- =============================================
CREATE TABLE message_views (
    view_id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    viewed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    device_info VARCHAR(255),
    ip_address INET,
    
    CONSTRAINT uq_message_view UNIQUE(message_id, user_id),
    CONSTRAINT fk_message_views_message FOREIGN KEY (message_id) 
        REFERENCES messages(message_id) ON DELETE CASCADE,
    CONSTRAINT fk_message_views_user FOREIGN KEY (user_id) 
        REFERENCES users(user_id) ON DELETE CASCADE
);

-- =============================================
-- 8. ТАБЛИЦА ПОСЛЕДНИХ СООБЩЕНИЙ ДИАЛОГОВ
-- =============================================
CREATE TABLE conversation_last_messages (
    conversation_id BIGINT NOT NULL,
    last_message_id BIGINT NOT NULL,
    last_message_time TIMESTAMP WITH TIME ZONE NOT NULL,
    last_message_type VARCHAR(20),
    last_sender_id BIGINT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT pk_conversation_last_messages PRIMARY KEY (conversation_id),
    CONSTRAINT uq_last_message_id UNIQUE(last_message_id),
    CONSTRAINT fk_clm_conversation FOREIGN KEY (conversation_id) 
        REFERENCES conversations(conversation_id) ON DELETE CASCADE,
    CONSTRAINT fk_clm_message FOREIGN KEY (last_message_id) 
        REFERENCES messages(message_id) ON DELETE CASCADE,
    CONSTRAINT fk_clm_sender FOREIGN KEY (last_sender_id) 
        REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT chk_message_time_not_future CHECK (last_message_time <= CURRENT_TIMESTAMP)
);

-- =============================================
-- 9. ТАБЛИЦА АУДИТА
-- =============================================
CREATE TABLE audit_log (
    audit_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    record_id BIGINT,
    operation VARCHAR(10) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    changed_by BIGINT,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ip_address INET,
    user_agent TEXT,
    
    CONSTRAINT fk_audit_log_changed_by FOREIGN KEY (changed_by) 
        REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT chk_operation CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),
    CONSTRAINT chk_old_new_values CHECK (
        (operation = 'INSERT' AND old_values IS NULL AND new_values IS NOT NULL) OR
        (operation = 'UPDATE' AND old_values IS NOT NULL AND new_values IS NOT NULL) OR
        (operation = 'DELETE' AND old_values IS NOT NULL AND new_values IS NULL) OR
        (operation = 'TRUNCATE' AND old_values IS NULL AND new_values IS NULL)
    )
);

-- =============================================
-- ИНДЕКСЫ ДЛЯ ОПТИМИЗАЦИИ ЗАПРОСОВ
-- =============================================

-- Индексы для таблицы users
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_created_at ON users(created_at);
CREATE INDEX idx_users_is_active ON users(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_users_last_seen ON users(last_seen DESC) WHERE status = 'online';
CREATE INDEX idx_users_search ON users USING gin(
    to_tsvector('english', username || ' ' || COALESCE(full_name, '') || ' ' || COALESCE(email, ''))
);
CREATE INDEX idx_users_phone_prefix ON users(phone varchar_pattern_ops) WHERE phone IS NOT NULL;

-- Индексы для таблицы contacts
CREATE INDEX idx_contacts_user_id ON contacts(user_id);
CREATE INDEX idx_contacts_contact_user_id ON contacts(contact_user_id);
CREATE INDEX idx_contacts_is_favorite ON contacts(is_favorite) WHERE is_favorite = TRUE;
CREATE INDEX idx_contacts_is_blocked ON contacts(is_blocked) WHERE is_blocked = TRUE;
CREATE INDEX idx_contacts_user_created ON contacts(user_id, created_at DESC);

-- Индексы для таблицы conversations
CREATE INDEX idx_conversations_type ON conversations(conversation_type);
CREATE INDEX idx_conversations_created_by ON conversations(created_by);
CREATE INDEX idx_conversations_updated_at ON conversations(updated_at DESC);
CREATE INDEX idx_conversations_created_at ON conversations(created_at DESC);
CREATE INDEX idx_conversations_is_active ON conversations(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_conversations_is_private ON conversations(is_private) WHERE is_private = TRUE;
CREATE INDEX idx_conversations_private_type ON conversations(conversation_type) WHERE conversation_type = 'private';

-- Индексы для таблицы conversation_members
CREATE INDEX idx_conversation_members_conversation_id ON conversation_members(conversation_id);
CREATE INDEX idx_conversation_members_user_id ON conversation_members(user_id);
CREATE INDEX idx_conversation_members_role ON conversation_members(role);
CREATE INDEX idx_conversation_members_joined_at ON conversation_members(joined_at DESC);
CREATE INDEX idx_conversation_members_is_muted ON conversation_members(is_muted) WHERE is_muted = TRUE;
CREATE INDEX idx_conversation_members_is_pinned ON conversation_members(is_pinned) WHERE is_pinned = TRUE;
CREATE INDEX idx_conversation_members_user_left ON conversation_members(user_id, left_at) WHERE left_at IS NULL;
CREATE INDEX idx_conversation_members_conversation_user ON conversation_members(conversation_id, user_id, left_at) WHERE left_at IS NULL;
CREATE INDEX idx_conversation_members_active ON conversation_members(conversation_id) WHERE left_at IS NULL;

-- Индексы для таблицы files
CREATE INDEX idx_files_uploader_id ON files(uploader_id);
CREATE INDEX idx_files_upload_date ON files(upload_date DESC);
CREATE INDEX idx_files_mime_type ON files(mime_type);
CREATE INDEX idx_files_file_size ON files(file_size);
CREATE INDEX idx_files_md5_hash ON files(md5_hash);
CREATE INDEX idx_files_sha256_hash ON files(sha256_hash);

-- Индексы для таблицы messages
CREATE INDEX idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_sent_at ON messages(sent_at DESC);
CREATE INDEX idx_messages_parent_message_id ON messages(parent_message_id);
CREATE INDEX idx_messages_conversation_sent ON messages(conversation_id, sent_at DESC);
CREATE INDEX idx_messages_type_sent ON messages(message_type, sent_at DESC);
CREATE INDEX idx_messages_is_deleted ON messages(is_deleted) WHERE is_deleted = FALSE;
CREATE INDEX idx_messages_is_edited ON messages(is_edited) WHERE is_edited = TRUE;
CREATE INDEX idx_messages_deleted_by ON messages(deleted_by) WHERE deleted_by IS NOT NULL;
CREATE INDEX idx_messages_search ON messages USING gin(search_vector);
CREATE INDEX idx_messages_conversation_type_sent ON messages(conversation_id, message_type, sent_at DESC);
CREATE INDEX idx_messages_sender_conversation ON messages(sender_id, conversation_id, sent_at DESC);
CREATE INDEX idx_messages_deleted_at ON messages(deleted_at DESC) WHERE is_deleted = TRUE;

-- Составные индексы для оптимизации частых запросов
CREATE INDEX idx_messages_conversation_unread ON messages(conversation_id, sent_at DESC) 
    WHERE is_deleted = FALSE;

CREATE INDEX idx_messages_user_activity ON messages(sender_id, sent_at DESC) 
    WHERE is_deleted = FALSE AND message_type NOT IN ('system', 'service');

-- BRIN индексы для временных данных
CREATE INDEX idx_messages_sent_at_brin ON messages USING BRIN (sent_at);
CREATE INDEX idx_message_views_viewed_at_brin ON message_views USING BRIN (viewed_at);
CREATE INDEX idx_audit_log_changed_at_brin ON audit_log USING BRIN (changed_at);

-- Индексы для таблицы message_views
CREATE INDEX idx_message_views_message_id ON message_views(message_id);
CREATE INDEX idx_message_views_user_id ON message_views(user_id);
CREATE INDEX idx_message_views_viewed_at ON message_views(viewed_at DESC);
CREATE INDEX idx_message_views_user_message ON message_views(user_id, message_id);

-- Индексы для таблицы conversation_last_messages
CREATE INDEX idx_conversation_last_messages_time ON conversation_last_messages(last_message_time DESC);
CREATE INDEX idx_conversation_last_messages_updated ON conversation_last_messages(updated_at DESC);
CREATE INDEX idx_conversation_last_messages_sender ON conversation_last_messages(last_sender_id);
CREATE INDEX idx_conversation_last_messages_type ON conversation_last_messages(last_message_type);

-- Индексы для таблицы audit_log
CREATE INDEX idx_audit_log_table_name ON audit_log(table_name);
CREATE INDEX idx_audit_log_operation ON audit_log(operation);
CREATE INDEX idx_audit_log_changed_by ON audit_log(changed_by);
CREATE INDEX idx_audit_log_record_id ON audit_log(record_id);
CREATE INDEX idx_audit_log_changed_at ON audit_log(changed_at DESC);
CREATE INDEX idx_audit_log_table_record ON audit_log(table_name, record_id, changed_at DESC);

-- GIN индексы для JSONB полей
CREATE INDEX idx_conversation_members_notification_gin ON conversation_members USING GIN (notification_settings);
CREATE INDEX idx_conversation_members_permissions_gin ON conversation_members USING GIN (permissions);
CREATE INDEX idx_conversations_metadata_gin ON conversations USING GIN (metadata);
CREATE INDEX idx_messages_entities_gin ON messages USING GIN (entities);
CREATE INDEX idx_audit_log_old_values_gin ON audit_log USING GIN (old_values);
CREATE INDEX idx_audit_log_new_values_gin ON audit_log USING GIN (new_values);

-- =============================================
-- ТЕСТОВЫЕ ДАННЫЕ
-- =============================================

-- 1. Пользователи
INSERT INTO users (user_id, username, email, phone, password_hash, full_name, status, is_verified, date_of_birth, created_at, last_seen, bio) VALUES
(1, 'alex2026', 'alex@example.com', '+79161234567', '$2a$12$hash1', 'Алексей Петров', 'online', true, '1995-03-15', '2025-12-01 10:00:00+03', '2026-01-31 09:30:00+03', 'Разработчик, увлекаюсь технологиями'),
(2, 'maria_tech', 'maria@example.com', '+79169876543', '$2a$12$hash2', 'Мария Сидорова', 'away', true, '1993-08-22', '2025-12-02 11:00:00+03', '2026-01-31 08:45:00+03', 'Дизайнер UI/UX'),
(3, 'ivan_dev', 'ivan@example.com', '+79991234567', '$2a$12$hash3', 'Иван Иванов', 'offline', true, '1990-11-10', '2025-12-03 12:00:00+03', '2026-01-30 22:15:00+03', 'Team Lead, менеджер проектов');

-- 2. Контакты
INSERT INTO contacts (user_id, contact_user_id, nickname, is_favorite, created_at) VALUES
(1, 2, 'Мария', true, '2025-12-10 10:00:00+03'),
(1, 3, 'Иван', false, '2025-12-11 11:00:00+03'),
(2, 1, 'Алексей', true, '2025-12-10 12:00:00+03'),
(2, 3, 'Иван', false, '2025-12-12 14:00:00+03'),
(3, 1, 'Алексей', true, '2025-12-11 15:00:00+03'),
(3, 2, 'Мария', false, '2025-12-13 16:00:00+03');

-- 3. Беседы
INSERT INTO conversations (conversation_id, conversation_type, title, created_by, created_at) VALUES
(1, 'private', NULL, 1, '2025-12-20 09:00:00+03'),
(2, 'group', 'Команда проекта', 2, '2025-12-21 10:00:00+03'),
(3, 'channel', 'Tech News 2026', 3, '2025-12-22 11:00:00+03');

-- 4. Участники бесед
INSERT INTO conversation_members (conversation_id, user_id, role, is_pinned, joined_at) VALUES
-- Беседа 1 (личная Алексей-Мария)
(1, 1, 'owner', true, '2025-12-20 09:00:00+03'),
(1, 2, 'member', true, '2025-12-20 09:00:00+03'),
-- Беседа 2 (групповая все 3 пользователя)
(2, 1, 'admin', false, '2025-12-21 10:00:00+03'),
(2, 2, 'owner', true, '2025-12-21 10:00:00+03'),
(2, 3, 'member', false, '2025-12-21 10:05:00+03'),
-- Беседа 3 (канал)
(3, 1, 'member', false, '2025-12-22 11:00:00+03'),
(3, 2, 'member', false, '2025-12-22 11:00:00+03'),
(3, 3, 'owner', true, '2025-12-22 11:00:00+03');

-- 5. Файлы
INSERT INTO files (file_id, original_filename, stored_filename, file_path, file_size, mime_type, uploader_id, upload_date) VALUES
(1, 'january_report.pdf', 'report_jan26.pdf', '/uploads/2026/01/report_jan26.pdf', 3123456, 'application/pdf', 1, '2026-01-15 10:00:00+03'),
(2, 'meeting_notes.docx', 'meeting_31jan.docx', '/uploads/2026/01/meeting_31jan.docx', 1048576, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 2, '2026-01-30 11:00:00+03'),
(3, 'project_diagram.png', 'diagram_project.png', '/uploads/2026/01/diagram_project.png', 2048576, 'image/png', 3, '2026-01-28 12:00:00+03');

-- 6. Сообщения
INSERT INTO messages (message_id, conversation_id, sender_id, message_type, content, file_id, sent_at) VALUES
-- Беседа 1 (личная Алексей-Мария)
(1, 1, 1, 'text', 'Привет! Как дела?', NULL, '2026-01-31 09:00:00+03'),
(2, 1, 2, 'text', 'Привет! Все хорошо, готовлюсь к встрече в 11:00', NULL, '2026-01-31 09:05:00+03'),
(3, 1, 1, 'text', 'Отлично! У меня готов отчет за январь', NULL, '2026-01-31 09:10:00+03'),
(4, 1, 1, 'file', 'Вот отчет по проекту', 1, '2026-01-31 09:15:00+03'),
(5, 1, 2, 'text', 'Спасибо! Посмотрю перед встречей', NULL, '2026-01-31 09:20:00+03'),

-- Беседа 2 (групповая)
(6, 2, 2, 'text', 'Коллеги, доброе утро! Напоминаю про встречу в 11:00', NULL, '2026-01-31 08:30:00+03'),
(7, 2, 3, 'text', 'Я готов. Принесу обновленные данные по проекту', NULL, '2026-01-31 08:35:00+03'),
(8, 2, 1, 'text', 'У меня готов отчет, только что отправил Марии', NULL, '2026-01-31 09:25:00+03'),
(9, 2, 2, 'file', 'Повестка встречи', 2, '2026-01-31 09:30:00+03'),
(10, 2, 3, 'image', 'Диаграмма архитектуры проекта', 3, '2026-01-31 09:40:00+03'),
(11, 2, 2, 'text', 'Отлично! До встречи через час', NULL, '2026-01-31 09:45:00+03'),

-- Беседа 3 (канал)
(12, 3, 3, 'text', 'Важное обновление: миграция на новые серверы завершена успешно', NULL, '2026-01-30 18:00:00+03'),
(13, 3, 3, 'text', 'Напоминание: бэкап данных перед обновлением ПО - 1 февраля', NULL, '2026-01-31 08:00:00+03');

-- 7. Просмотры сообщений
INSERT INTO message_views (message_id, user_id, ip_address, viewed_at) VALUES
-- Просмотры в беседе 1
(1, 2, '192.168.1.2', '2026-01-31 09:01:00+03'),
(2, 1, '192.168.1.1', '2026-01-31 09:06:00+03'),
(3, 2, '192.168.1.2', '2026-01-31 09:11:00+03'),
(4, 2, '192.168.1.2', '2026-01-31 09:16:00+03'),
(5, 1, '192.168.1.1', '2026-01-31 09:21:00+03'),

-- Просмотры в беседе 2
(6, 1, '192.168.1.1', '2026-01-31 08:31:00+03'),
(6, 3, '192.168.1.3', '2026-01-31 08:32:00+03'),
(7, 1, '192.168.1.1', '2026-01-31 08:36:00+03'),
(7, 2, '192.168.1.2', '2026-01-31 08:37:00+03'),
(8, 2, '192.168.1.2', '2026-01-31 09:26:00+03'),
(8, 3, '192.168.1.3', '2026-01-31 09:27:00+03'),
(9, 1, '192.168.1.1', '2026-01-31 09:31:00+03'),
(9, 3, '192.168.1.3', '2026-01-31 09:32:00+03'),
(10, 1, '192.168.1.1', '2026-01-31 09:41:00+03'),
(10, 2, '192.168.1.2', '2026-01-31 09:42:00+03'),
(11, 1, '192.168.1.1', '2026-01-31 09:46:00+03'),
(11, 3, '192.168.1.3', '2026-01-31 09:47:00+03'),

-- Просмотры в беседе 3
(12, 1, '192.168.1.1', '2026-01-30 18:05:00+03'),
(12, 2, '192.168.1.2', '2026-01-30 18:10:00+03'),
(13, 1, '192.168.1.1', '2026-01-31 08:05:00+03'),
(13, 2, '192.168.1.2', '2026-01-31 08:10:00+03');

-- 8. Последние сообщения
INSERT INTO conversation_last_messages (conversation_id, last_message_id, last_message_time, last_message_type, last_sender_id) VALUES
(1, 5, '2026-01-31 09:20:00+03', 'text', 2),
(2, 11, '2026-01-31 09:45:00+03', 'text', 2),
(3, 13, '2026-01-31 08:00:00+03', 'text', 3);

-- 9. Аудит-лог
INSERT INTO audit_log (table_name, record_id, operation, old_values, new_values, changed_by, ip_address, changed_at) VALUES
('users', 1, 'UPDATE', '{"status": "offline"}', '{"status": "online"}', 1, '192.168.1.1', '2026-01-31 09:00:00+03'),
('messages', 1, 'INSERT', NULL, '{"content": "Привет! Как дела?", "sender_id": 1, "conversation_id": 1}', 1, '192.168.1.1', '2026-01-31 09:00:00+03'),
('files', 2, 'INSERT', NULL, '{"original_filename": "meeting_notes.docx", "uploader_id": 2}', 2, '192.168.1.2', '2026-01-30 11:00:00+03');

-- =============================================
-- ПРОВЕРКА ДАННЫХ
-- =============================================

-- Количество записей
SELECT 
    'users' as table_name, COUNT(*) FROM users
UNION ALL SELECT 'contacts', COUNT(*) FROM contacts
UNION ALL SELECT 'conversations', COUNT(*) FROM conversations
UNION ALL SELECT 'conversation_members', COUNT(*) FROM conversation_members
UNION ALL SELECT 'files', COUNT(*) FROM files
UNION ALL SELECT 'messages', COUNT(*) FROM messages
UNION ALL SELECT 'message_views', COUNT(*) FROM message_views
UNION ALL SELECT 'conversation_last_messages', COUNT(*) FROM conversation_last_messages
UNION ALL SELECT 'audit_log', COUNT(*) FROM audit_log
ORDER BY table_name;

-- Компактный вывод всех данных
SELECT '=== USERS ===' as table_name; SELECT * FROM users ORDER BY user_id;
SELECT '=== CONTACTS ===' as table_name; SELECT * FROM contacts ORDER BY contact_id;
SELECT '=== CONVERSATIONS ===' as table_name; SELECT * FROM conversations ORDER BY conversation_id;
SELECT '=== CONVERSATION_MEMBERS ===' as table_name; SELECT * FROM conversation_members ORDER BY member_id;
SELECT '=== FILES ===' as table_name; SELECT * FROM files ORDER BY file_id;
SELECT '=== MESSAGES ===' as table_name; SELECT * FROM messages ORDER BY message_id;
SELECT '=== MESSAGE_VIEWS ===' as table_name; SELECT * FROM message_views ORDER BY view_id;
SELECT '=== CONVERSATION_LAST_MESSAGES ===' as table_name; SELECT * FROM conversation_last_messages ORDER BY conversation_id;
SELECT '=== AUDIT_LOG ===' as table_name; SELECT * FROM audit_log ORDER BY audit_id;