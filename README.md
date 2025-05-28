# DTMF Digital Mode Changer for DVSwitch 

William M. Mongan
December 1, 2024

## Installation and Configuration

Clone this repository to your AllStar node `/opt` directory, via:

```
cd /opt
git clone https://github.com/BillJr99/digital_link
```

Within the `digital_link` directory, there is a minimal amount of configuration.  Copy the file `switch_modes.conf.sample` to `switch_modes.conf`, and create as many sections as you like.  Some modes do not need all the fields, and these are set to NA in the template.  The `modemaster` defines the first two DTMF tones one will send to link to that mode and master.  For example, `12` will select the TGIF network on DMR, since `1` represents DMR, and `2` represents TGIF. Ensure that all masters within the same mode have the same first `modemaster` digit: for example, all DMR networks should have a first `modemaster` digit of `1`, and all D-STAR networks should have a first `modemaster` digit of `2`.  The actual digit is your choice, as long as you do not select `0` for the mode or the master digit (these are reserved for unlinking).  Set the `mode` to `DMR`, `D-STAR`, `YSF`, `NXDN`, or `P25` as appropriate, as well as the host, port, and password, if applicable.

Within `digital_link.sh`, set your AllStar node number and linked digital node (i.e., `1999`) for `NODE_ID` and `LINKED_NODE_ID`, respectively.

Finally, ensure that `/opt/digital_link/dvswitch_links.log` is owned by the `asterisk` user, and that the `digital_link.sh` script is executable:

```
sudo touch dvswitch_links.log
sudo chown asterisk:asterisk dvswitch_links.log
chmod a+x digital_link.sh
```

## Mapping to Asterisk

You can assign a dialplan to Asterisk so that the DTMF tones for a given code pattern will be forwarded to this script.  I used `AA` as my entry code, and recommend choosing the same two-digit/character sequence.  This is important because the `rpt.conf` will read and consume the first digit, and then pass the remaining to the dialplan.  The second digit allows the dialplan to match the rest of the string, in case you have other dialplan patterns in place.  This resulting string (starting with a single `A`) is passed to the script for parsing.

### `/etc/asterisk/rpt.conf`

Modify `rpt.conf` under the `[functions]` section by adding the following line (replace `A` with the DTMF tone you'd like to match to run the script):

```
A = autopatchup,context=digital_link,noct=1,farenddisconnect=1,dialtime=60000,quiet=1
```

### `/etc/asterisk/extensions.conf`

Modify `extensions.conf` by adding the following stanza (again, replace `_A.` with `_@.`, where `@` is the DTMF tone you used in `rpt.conf` above):

```
[digital_link]
exten => _A.,n(normal),System(/opt/digital_link/digital_link.sh ${EXTEN})
exten => _A.,n,Hangup
```

## Usage

Assuming you used `A` to start the `autopatch` and for the `exten` rules above, you can send the following DTMF tones to your AllStarLink node to activate DVSwitch, change/unlink modes, and change/unlink talkgroups.  All commands will begin with `*AA`.  The first `A` is provided to Asterisk, the second `A` is matched by the autopatch extension rules, and the entire string starting with (and including) the second `A` is passed to the `digital_link.sh` script and parsed.

```
*AA <mode digit> <master> <optional TG> <optional D key>
```

* `<mode digit>`: The mode digit is the first digit in `switch_modes.conf` that corresponds to the `modemaster` of the master and/or talkgroup you wish to connect to.  For example, DMR corresponds to `1`, and D-STAR corresponds to `2` in the template provided by `switch_modes.conf`.
* `<master>`: The master digit is the second digit in `switch_modes.conf` that corresponds to the `modemaster` of the master and/or talkgorup you wish to connect to.  For example, Brandmeister corresponds to `1` and TGIF corresponds to `2` for DMR, and REF corresponds to `1` and XLX corresponds to `2` for D-STAR.  
* `<TG>`: The talkgroup you wish to connect to; for example, 9999.  This can be omitted if there is no specific talkgroup on the master being connected to (i.e., when using YSF).  On D-STAR, this is the numeric component, so to connect to `REF030C`, one would press the digit corresponding to `REF` for the `<master>` digit previously, and then enter `030C`.
* `<optional D key>`: Sending the `D` DTMF tone at the end of the command indicates that a private call should be made on DMR, or to link to the `Echo` repeater on D-STAR.  This is translated to a `#` character and passed to DVSwitch as either a escaped `#` character, or as the `E` echo tone on D-STAR, as appropriate.

### Linking

The first time you issue one of these commands, Asterisk will unlink from any connected nodes other than your digital-analog bridge node (i.e., `1999`), and link to your digital-analog bridge node if it wasn't already linked.

### Examples

These examples assume the stock configuration in `digital_link.sh`, with spaces added to the commands for clarity (note that the entire set of tones is entered as a single transmission):

* Connect to REF030C on D-STAR: `*AA 21 030C`
* Connect to REF001E on D-STAR: `*AA 21 001D`
* Connect to 9990 (Private call) on DMR Brandmeister: `*AA 11 9990D`
* Connect to TG 91 on DMR Brandmeister: `*AA 11 91`
* Connect to Parrot on YSF: `*AA 31`
* Connect to AmericaLink on YSF: `*AA 32`
* Connect to TG 101 on DMR TGIF: `*AA 12 101`

### Unlinking

When you switch modes, the unlink command for the current mode is issued.  You can force an unlink by entering `*AA 0`.  If you wish to unlink from the current digital mode and also unlink from your digital-analog bridge node entirely on AllStar, you can enter `*AA 00`.

## Disclaimer

This software is only lightly tested and should be considered in beta.  Your testing, feedback, and contributions are most welcome.  Please be sure to have a backup of your configurations, and be sure to check that the modes are correctly linked / unlinked!