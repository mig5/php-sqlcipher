# SQLCipher for PHP `sqlite3` / `pdo_sqlite` (Debian & Ubuntu)

This repo contains build scripts and a `reprepro` APT repository for **drop-in replacements** of PHP’s `sqlite3` and `pdo_sqlite` extensions, recompiled against [**SQLCipher**](https://www.zetetic.net/sqlcipher/) (encrypted SQLite).

> These packages are intended to **replace** the phpX.Y-sqlite3 from Ondřej Surý’s PHP repo, linked against SQLCipher instead of the stock SQLite library. The driver name itself does not change.

---

## Supported PHP & OS versions

* **PHP:** 7.4, 8.0, 8.1, 8.2, 8.3, 8.4
* **OS:** Debian **12 (bookworm)**, Debian **13 (trixie)**, Ubuntu **22.04 (jammy)**, Ubuntu **24.04 (noble)**

> **Assumption:** You’re using PHP from [**Ondřej Surý**](https://deb.sury.org) (packages.sury.org / PPA) on both Debian and Ubuntu. If not, you may need to edit the scripts to fetch `apt-get source phpX.Y` differently.

---

## How I build and test the packages

I use Docker to help me build the packages. Sorry if you don't like it, but I find it very convenient for handling different distributions (and also as it allows me some hardening measures, see below).

Since this is a security-focused package, consider the following information carefully.

I build, test and sign these deb packages **locally** using the following:

 * Docker, using the [gvisor/runsc](https://gvisor.dev) hardened runtime.
 * The actual compile and deb build steps occur as an **unprivileged** user in the Docker container, with **no network access**. Network access is only enabled to install the dependencies
 * My Docker daemon runs inside an ephemeral, disposable [QubesOS](https://qubes-os.org) VM that only has port 80/443 access outbound (for apt repositories and git repo cloning). Qubes is a compartmentalised and reasonably-secure operating system.
 * The GPG key that signs the packages is on a Yubikey. The GPG key is accessed by the Qubes VM via a Qubes 'vault' VM across Qubes' backplane - the Qubes VM has no direct access to the key on the filesystem or even to the USB device, except when I'm prompted to sign the package.
 * The GPG private key does not exist on the apt repository server or in fact **anywhere** other than on the Yubikey.
 * The signing and apt repo preparation for the built and tested .deb packages, happens in a **separate Qubes VM** to the build machine, that has **no network access** at all.

I consider this reasonably, perhaps even **quite** secure for my use case - but it's not 100% reproducible and it *does* require network access for brief periods.


## Option 1: use my APT repository

I publish the packages I built, in my own apt repository, using the process described above.

However, you have no reason to trust me and my apt repository. This repository exists so that you can build the packages yourself instead. See Option 2 for that.

### 1) Add the GPG key (signed-by)

```bash
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://mig5.net/static/mig5.asc | sudo gpg --dearmor -o /usr/share/keyrings/mig5.gpg
```

My GPG fingerprint is `00AE817C24A10C2540461A9C1D7CDE0234DB458D`. You can also fetch it from https://keys.openpgp.org or search the fingerprint online to confirm it.

### 2) Add the APT source

**Debian 12 (bookworm):**

```bash
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/mig5.gpg] https://apt.mig5.net bookworm main" | sudo tee /etc/apt/sources.list.d/mig5.list
```

**Debian 13 (trixie):**

```bash
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/mig5.gpg] https://apt.mig5.net trixie main" | sudo tee /etc/apt/sources.list.d/mig5.list
```

**Ubuntu 22.04 (jammy):**

```bash
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/mig5.gpg] https://apt.mig5.net jammy main" | sudo tee /etc/apt/sources.list.d/mig5.list
```

**Ubuntu 24.04 (noble):**

```bash
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/mig5.gpg] https://apt.mig5.net noble main" | sudo tee /etc/apt/sources.list.d/mig5.list
```

### 3) Update & install

```bash
sudo apt update
# (example: PHP 8.2)
sudo apt install php8.2-sqlcipher
```

> Remember: These packages are built to **replace** `phpX.Y-sqlite3` with a SQLCipher-linked build.

### 4) (Recommended) Pin to prefer this repo for sqlcipher packages

Create `/etc/apt/preferences.d/mig5.pref`:

```ini
Package: php*-sqlcipher
Pin: release o=mig5, l=php-sqlcipher, n=bookworm # adjust to your distro
Pin-Priority: 990
```

Then:

```bash
sudo apt update
apt-cache policy php8.2-sqlcipher
```

You should see this repo as the selected candidate.

---

## Option 2: Building your own .debs

If you’d rather build locally, use `scripts/package.sh` which executes the Docker build process.

```bash
./scripts/package.sh
```

See the top of the script for the matrix of PHP versions and distros to build for.

---

## Using SQLCipher for PHP

```php
<?php
  try {
    $dbh = new PDO("sqlite:/tmp/test.db");
    $dbh->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $dbh->exec("PRAGMA key = 'super secret passphrase goes here'");
    $dbh->exec("PRAGMA cipher_memory_security = ON");
    $create = "CREATE TABLE IF NOT EXISTS users (name TEXT NOT NULL)";
    $dbh->exec($create);
    $insert = "INSERT INTO users(name) VALUES(:name)";
    $stmt = $dbh->prepare($insert);
    $stmt->bindValue(":name", "mig5");
    $stmt->execute();
    echo "Last insert ID: " . $dbh->lastInsertId() . "\n";
  } catch (Exception $e) {
    echo $e->getMessage();
    exit(1);
  }
```

See more documentation on the SQLCipher PRAGMAs at https://www.zetetic.net/sqlcipher/sqlcipher-api/

---

## Verifying SQLCipher is actually in use

Look at the `tests/test_sqlcipher.php` script. This performs a battery of tests against a database to make sure it looks encrypted with SQLCipher.

The test script is used by `autopkgtest` during the build, and can also be found in `/usr/share/doc/phpX.Y-sqlcipher/examples` on a system that has installed the deb package.

Another technique: run `hexdump -C` on the created database. It should show totally scrambled content.

Another technique would be to try and open it with regular SQLite (don't pass `PRAGMA key` as the first query). It should throw an error that it couldn't open the database.

---

## Notes on compatibility

* These are drop-in **replacements** of the distro's official PHP `sqlite3`/`pdo_sqlcipher` extensions, just linked to SQLCipher.
* You should still be able to use regular SQLite3 databases with these packages.
* You must be on **Ondřej Surý’s PHP packages** to match headers and packaging expectations.

---

## Troubleshooting

* **Module not loading?** Check `php -m | grep sqlite` and `php --ri sqlite3`.
* **Still using stock SQLite?** Ensure the package came from this repo (`apt-cache policy phpX.Y-sqlite3`).
* **Encrypted DB won’t open?** Make sure you’re calling `PRAGMA key` **before** any queries, and that the cipher settings (e.g., `cipher_compatibility`) match the DB’s format.
* See the `tests` folder for some sample read/write PHP scripts.

---

## License

SQLCipher, PHP itself and the PHP extensions are licensed under their respective upstream licenses. See `debian/copyright.in` in this repository.

My own build scripts (e.g everything that is not part of SQLCipher or PHP themselves, here) are in the public domain.

---

## No warranty

This software and repository are provided **“as is”**, **without warranty of any kind**. You assume **all** risk for installing and using these packages or scripts. No liability is accepted for any form of data loss, security issues, or any other damages, even if they resulted from bugs I introduced.

---

## Acknowledgements

This project began as far back as 2013 for [Mydex Data Services CIC](https://mydex.org). Thanks to Mydex for encouraging me to open source the build tooling for others.

Thanks to Ondřej Surý for many years of tireless packaging of PHP versions for Debian and Ubuntu. [Please support him!](https://deb.sury.org/#support)

Thanks to Zetetic for creating and maintaining SQLCipher, and for keeping it open source for the community.

---

## Contact / issues

You can contact me via the contact form at https://mig5.net or on GotoSocial ([@mig5@goto.mig5.net](https://goto.mig5.net/@mig5).

 * Are you looking for a contract/freelance sysadmin to help harden and/or maintain your Linux infrastructure, CI/CD workflows or tighten up your security?
 * In the US or Europe and need a senior Linux expert to help mentor your internal team, or handle the night shift?
 * Need SQLCipher packaged for a different version of PHP or Linux?

Good news, that's been my bread and butter since 2007. Please visit [my website](https://mig5.net) to learn more and get in touch.
