#!/usr/bin/env python

"""email-update.py is a tool for sending an updated list of HTTP sites
requiring authentication via client certificates

Usage:
  email-update.py --db-creds-file=FILENAME --from=EMAIL --to=EMAIL [--cc=EMAIL] [--reply=EMAIL] --subject=SUBJECT --text=FILENAME --html=FILENAME [--log-level=LEVEL]
  email-update.py (-h | --help)

Options:
  -h --help         Show this message.
  --db-creds-file=FILENAME  A YAML file containing the BOD 18-01 scan results database credentials.
  --from=EMAIL      The email address from which the updated information should be sent.
  --to=EMAIL        A comma-separated list email address where the updated information should be sent.
  --cc=EMAIL        A comma-separated list email address where the updated information should also be sent.
  --reply=EMAIL     The email address to use as the reply-to address when sending the updated information.
  --subject=SUBJECT The subject to use when sending the updated information.
  --text=FILENAME   The name of a file containing the plain text that is to be used as the body of the email when sending the updated information.
  --html=FILENAME   The name of a file containing the HTML text that is to be used as the body of the email when sending the updated information.
  --log-level=LEVEL If specified, then the log level will be set to the specified value.  Valid values are "debug", "info", "warning", and "error".

"""

from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import gzip
import json
import logging

import boto3
import docopt
from mongo_db_from_config import db_from_config
import pymongo.errors
import yaml


def query(db):
    """Query the BOD 18-01 scan results database for hosts that require
    authentication via client certificates

    Parameters
    ----------
    db : mongokit.database.Database
         The Mongo database connection

    Returns
    -------
    list: A list of dicts, each containing the pshtt scan results for
    a single host that requires authentication via client
    certificates.

    """
    client_cert_hosts = db.https_scan.find(
        {"latest": True, "live": True, "https_client_auth_required": True},
        {"_id": False, "scan_date": False, "latest": False},
    )

    return list(client_cert_hosts)


def main():
    # Parse command line arguments
    args = docopt.docopt(__doc__)

    # Set up logging
    log_level = logging.getLevelName(logging.WARNING)
    if args["--log-level"]:
        log_level = args["--log-level"]
    try:
        logging.basicConfig(
            format="%(asctime)-15s %(levelname)s %(message)s", level=log_level.upper()
        )
    except ValueError:
        logging.critical(
            f'"{log_level}" is not a valid logging level.  Possible values are debug, info, warning, and error.'
        )
        return 1

    # Handle some command line arguments
    db_creds_file = args["--db-creds-file"]
    from_email = args["--from"]
    to_email = args["--to"]
    cc_email = args["--cc"]
    reply_email = args["--reply"]
    subject = args["--subject"]
    text_filename = args["--text"]
    html_filename = args["--html"]

    # Connect to the BOD 18-01 scan results database
    try:
        db = db_from_config(db_creds_file)
    except OSError:
        logging.critical(
            f"Database configuration file {db_creds_file} does not exist", exc_info=True
        )
        return 1
    except yaml.YAMLError:
        logging.critical(
            f"Database configuration file {db_creds_file} does not contain valid YAML",
            exc_info=True,
        )
        return 1
    except KeyError:
        logging.critical(
            f"Database configuration file {db_creds_file} does not contain the expected keys",
            exc_info=True,
        )
        return 1
    except pymongo.errors.ConnectionError:
        logging.critical(
            f"Unable to connect to the database server in {db_creds_file}",
            exc_info=True,
        )
        return 1
    except pymongo.errors.InvalidName:
        logging.critical(
            f"The database in {db_creds_file} does not exist", exc_info=True
        )
        return 1

    # Perform the query to retrieve all hosts that require
    # authentication via client certificates
    client_cert_hosts = query(db)

    # Build up the MIME message to be sent
    msg = MIMEMultipart("mixed")
    msg["From"] = from_email
    logging.debug(f"Message will be sent from: {from_email}")
    msg["To"] = to_email
    logging.debug(f"Message will be sent to: {to_email}")
    if cc_email is not None:
        msg["CC"] = cc_email
        logging.debug(f"Message will be sent as CC to: {cc_email}")
    if reply_email is not None:
        msg["Reply-To"] = reply_email
        logging.debug(f"Replies will be sent to: {reply_email}")
    msg["Subject"] = subject
    logging.debug(f"Message subject is: {subject}")

    # Construct and attach the text body
    body = MIMEMultipart("alternative")
    with open(text_filename, "r") as text:
        t = text.read()
        body.attach(MIMEText(t, "plain"))
        logging.debug(f"Message plain-text body is: {t}")
    with open(html_filename, "r") as html:
        h = html.read()
        html_part = MIMEText(h, "html")
        # See https://en.wikipedia.org/wiki/MIME#Content-Disposition
        html_part.add_header("Content-Disposition", "inline")
        body.attach(html_part)
        logging.debug(f"Message HTML body is: {h}")
    msg.attach(body)

    # Attach JSON file
    json_part = MIMEApplication(
        gzip.compress(
            json.dumps(client_cert_hosts, sort_keys=True, indent=4).encode("utf-8")
        ),
        "json",
    )
    json_part.add_header("Content-Encoding", "gzip")
    json_filename = "hosts_that_require_auth_via_client_certs.json.gz"
    # See https://en.wikipedia.org/wiki/MIME#Content-Disposition
    json_part.add_header("Content-Disposition", "attachment", filename=json_filename)
    logging.debug(f"Message will include file {json_filename} as attachment")
    msg.attach(json_part)

    # Send the email
    ses_client = boto3.client("ses")
    response = ses_client.send_raw_email(RawMessage={"Data": msg.as_string()})
    # Check for errors
    status_code = response["ResponseMetadata"]["HTTPStatusCode"]
    if status_code != 200:
        logging.error(f"Unable to send message.  Response from boto3 is: {response}")
        return 2

    # Stop logging and clean up
    logging.shutdown()


if __name__ == "__main__":
    main()
