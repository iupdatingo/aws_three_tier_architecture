<?php
// api/db_connection.php

/**
 * Get database connection.
 *
 * The database login details are NOT stored in this repository.
 * They are read from a settings file on the app-tier server:
 *
 *     /etc/three-tier-app/db.ini
 *
 * Copy backend/db.ini.example to that path and fill in your values.
 * Environment variables (DB_HOST, DB_NAME, DB_USER, DB_PASSWORD) can be
 * used instead, and take priority over the file if they are set.
 *
 * @return PDO
 */
function getDatabaseConnection() {
    $configFile = '/etc/three-tier-app/db.ini';
    $config = [];

    if (is_readable($configFile)) {
        $parsed = parse_ini_file($configFile, false, INI_SCANNER_RAW);
        if ($parsed !== false) {
            $config = $parsed;
        }
    }

    $host     = getenv('DB_HOST')     ?: ($config['DB_HOST']     ?? '');
    $db_name  = getenv('DB_NAME')     ?: ($config['DB_NAME']     ?? 'hello_world');
    $username = getenv('DB_USER')     ?: ($config['DB_USER']     ?? '');
    $password = getenv('DB_PASSWORD') ?: ($config['DB_PASSWORD'] ?? '');

    if ($host === '' || $username === '') {
        throw new PDOException(
            "Database settings not found. Create $configFile from backend/db.ini.example."
        );
    }

    $dsn = "mysql:host=$host;dbname=$db_name;charset=utf8mb4";
    $options = [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ];

    return new PDO($dsn, $username, $password, $options);
}
?>
