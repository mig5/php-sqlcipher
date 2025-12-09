<?php
declare(strict_types=1);

/**
 * SQLCipher verification script
 *
 * WHAT IT CHECKS
 *  1) PRAGMA key is correctly applied (and cipher_version is non-empty).
 *  2) PRAGMA cipher_integrity_check returns NO ROWS (OK).
 *  3) File header is NOT the plain "SQLite format 3\0".
 *  4) Inserting a known plaintext marker does NOT make that marker appear in the raw file.
 *  5) Opening with a wrong key fails to validate via cipher_integrity_check.
 *  6) First-page entropy is high (sanity check).
 */

// ---------------------------- Utilities ----------------------------

function makePrivateTempDir(?string $base = null): string {
    $base = $base ?? sys_get_temp_dir();
    $oldUmask = umask(0077);
    try {
        for ($i = 0; $i < 5; $i++) {
            $name = bin2hex(random_bytes(16));
            $dir  = $base . DIRECTORY_SEPARATOR . "php-$name";
            if (@mkdir($dir, 0700)) {
                return realpath($dir) ?: $dir;
            }
        }
        throw new RuntimeException("Could not create a unique temp directory");
    } finally {
        umask($oldUmask);
    }
}

/** Simple pretty assertion helper */
function check(string $label, bool $ok, ?string $detail = null): void {
    $prefix = $ok ? "[OK] " : "[FAIL] ";
    echo $prefix . $label . ($detail ? " — $detail" : "") . "\n";
    if (!$ok) {
        exit(1);
    }
}

/** Return true if the file begins with the plain SQLite header */
function hasPlainSQLiteHeader(string $path): bool {
    $fh = @fopen($path, 'rb');
    if (!$fh) {
        throw new RuntimeException("Cannot open $path");
    }
    $hdr = fread($fh, 16);
    fclose($fh);
    return $hdr === "SQLite format 3\0";
}

/** Shannon entropy (bits/byte) */
function shannonEntropy(string $bytes): float {
    $len = strlen($bytes);
    if ($len === 0) return 0.0;
    $freq = count_chars($bytes, 1);
    $h = 0.0;
    foreach ($freq as $n) {
        $p = $n / $len;
        $h -= $p * log($p, 2);
    }
    return $h;
}

/** Read first page (minus the first 16 bytes salt) and estimate entropy */
function firstPageEntropy(string $path, int $pageSize = 4096): float {
    $fh = @fopen($path, 'rb');
    if (!$fh) throw new RuntimeException("Cannot open $path");
    $page = fread($fh, $pageSize);
    fclose($fh);
    if ($page === false || strlen($page) === 0) return 0.0;
    // SQLCipher uses first 16 bytes as salt at offset 0
    $slice = substr($page, 16);
    return shannonEntropy($slice);
}

/** Open PDO with SQLCipher key applied */
function pdoWithKey(string $path, string $passphrase): PDO {
    $dbh = new PDO("sqlite:" . $path);
    $dbh->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $dbh->exec("PRAGMA key = " . $dbh->quote($passphrase));
    $dbh->exec("PRAGMA cipher_memory_security = ON");
    return $dbh;
}

/** Return a single scalar from "PRAGMA xyz;" */
function pragmaOne(PDO $dbh, string $pragma): ?string {
    $stmt = $dbh->query("PRAGMA $pragma;");
    $row = $stmt ? $stmt->fetch(PDO::FETCH_NUM) : false;
    return $row && isset($row[0]) ? (string)$row[0] : null;
}

/**
 * cipher_integrity_check returns:
 *  - zero rows => OK (externally consistent)
 *  - one or more rows => errors found (or wrong key)
 */
function cipherIntegrityOk(PDO $dbh): bool {
    $stmt = $dbh->query("PRAGMA cipher_integrity_check;");
    if (!$stmt) return false;  // query failed -> not OK
    $row = $stmt->fetch(PDO::FETCH_NUM);
    return ($row === false);   // no rows == OK
}

/**
 * cipher_status returns:
 *  - 1 (ok)
 * https://www.zetetic.net/sqlcipher/sqlcipher-api/#cipher_status
 */
function cipherStatus(PDO $dbh): bool {
    $stmt = $dbh->query("PRAGMA cipher_status;");
    if (!$stmt) return false;  // query failed -> not OK
    $row = $stmt->fetch(PDO::FETCH_NUM);
    return ($row[0] == "1");
}

// ---------------------------- Main actions ----------------------------

function createAndPopulate(string $path, string $passphrase, string $marker): void {
    $dbh = pdoWithKey($path, $passphrase);

    // Basic SQLCipher sanity: cipher_version should be non-empty
    $cipherVersion = pragmaOne($dbh, "cipher_version");
    check("cipher_version available", !empty($cipherVersion), $cipherVersion ?? "(empty)");

    // Create table and insert two rows (one is the plaintext 'marker')
    $dbh->exec("CREATE TABLE IF NOT EXISTS users (name TEXT NOT NULL)");
    $stmt = $dbh->prepare("INSERT INTO users(name) VALUES(:name)");
    $stmt->execute([":name" => "mig5"]);
    $stmt->execute([":name" => $marker]);

    // Confirm we can read back with the correct key
    $names = $dbh->query("SELECT name FROM users ORDER BY rowid")->fetchAll(PDO::FETCH_COLUMN, 0);
    check("Read back inserted rows", in_array("mig5", $names, true) && in_array($marker, $names, true));

    // Integrity check should be OK (i.e., returns no rows)
    $ok = cipherIntegrityOk($dbh);
    check("cipher_integrity_check", $ok, $ok ? "no rows (OK)" : "reported errors");

    // Status check should be OK (new in 4.12.0 - returns 1 if ok)
    $ok = cipherStatus($dbh);
    check("cipher_status", $ok, $ok ? "row result = 1 (OK)" : "reported errors");

    // Capture page_size (for entropy sampling)
    $pageSize = (int)(pragmaOne($dbh, "page_size") ?? 4096);
    $dbh = null; // close
    // Store page size to a sidecar file so we can read it after closing the DB
    file_put_contents($path . ".pagesize", (string)$pageSize);
}

function probeWrongKey(string $path, string $wrongKey): void {
    try {
        $dbh = pdoWithKey($path, $wrongKey);

        // With the wrong key, integrity should NOT be OK (either rows returned or errors)
        $okWrong = false;
        try {
            $okWrong = cipherIntegrityOk($dbh); // true means "no rows" => (unexpected)
        } catch (Throwable $e) {
            // Expected scenarios with wrong key can throw; treat as failure (which is good here)
            $okWrong = false;
        }

        if ($okWrong) {
            check("Wrong key probe (unexpectedly OK)", false);
        } else {
            check("Wrong key probe (integrity fails as expected)", true);
        }
    } catch (Throwable $e) {
        // Exception creating/using the handle is also acceptable evidence key is wrong
        check("Wrong key probe (exception on use)", true, get_class($e) . ": " . $e->getMessage());
    }
}

function scanForPlaintextMarker(string $path, string $marker): void {
    $raw = file_get_contents($path);
    $found = ($raw !== false) && (strpos($raw, $marker) !== false);
    check("Plaintext marker NOT present in raw file", !$found, $found ? "marker leaked to disk" : null);
}

function headerIsNotPlainSQLite(string $path): void {
    $plain = hasPlainSQLiteHeader($path);
    check("Header is not plain 'SQLite format 3\\0'", !$plain, $plain ? "found plain SQLite header" : null);
}

function entropyCheck(string $path): void {
    $pageSizePath = $path . ".pagesize";
    $pageSize = 4096;
    if (is_file($pageSizePath)) {
        $ps = (int)trim((string)file_get_contents($pageSizePath));
        if ($ps > 0) $pageSize = $ps;
    }
    $H = firstPageEntropy($path, $pageSize);
    // Encrypted data typically ~7.8–8.0 bits/byte. Use a lenient threshold.
    $ok = $H >= 7.5;
    check("First-page entropy high (>= 7.5 bits/byte)", $ok, sprintf("H=%.3f (page=%d)", $H, $pageSize));
    @unlink($pageSizePath);
}

// ---------------------------- Run ----------------------------

try {
    $dir  = makePrivateTempDir();
    $file = $dir . DIRECTORY_SEPARATOR . 'test.db';

    $passphrase = "super-secret-passphrase-for-sqlcipher-pragma";
    $wrongKey   = "definitely-the-wrong-key";
    $marker     = "PLAINTEXT_MARKER_" . bin2hex(random_bytes(8));

    echo "Creating DB at: $file\n";
    createAndPopulate($file, $passphrase, $marker);

    headerIsNotPlainSQLite($file);
    scanForPlaintextMarker($file, $marker);
    probeWrongKey($file, $wrongKey);
    entropyCheck($file);

    echo "\nAll checks passed.\n";

} catch (Throwable $e) {
    fwrite(STDERR, "Error: " . get_class($e) . ": " . $e->getMessage() . "\n");
    exit(1);
} finally {
    // Cleanup
    if (isset($file) && is_file($file)) @unlink($file);
    if (isset($dir) && is_dir($dir)) @rmdir($dir);
}

