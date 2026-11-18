-- Creates the database and table that the PHP backend expects.
-- Run with:
--   mysql --host=YOUR-RDS-ENDPOINT --user=admin -p < database/schema.sql

CREATE DATABASE IF NOT EXISTS hello_world;
USE hello_world;

CREATE TABLE IF NOT EXISTS messages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO messages (message) VALUES ('Hello from the database tier');
INSERT INTO messages (message) VALUES ('Three tier architecture test');
INSERT INTO messages (message) VALUES ('Frontend to backend to RDS is working');
