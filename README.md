# sf6stats

[![Test](https://github.com/nekorobi/sf6stats/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/nekorobi/sf6stats/actions)

- Show fighting stats of STREET FIGHTER 6

## Features
- Color-coded win rates for better visualization:
  - Green: Win rates ≥ 5.5
  - Light Green: Win rates ≥ 5.2 and < 5.5
  - Default color: Win rates ≥ 4.8 and < 5.2
  - Light Red: Win rates ≥ 4.5 and < 4.8
  - Red: Win rates < 4.5
- Supports both light and dark terminal themes
- Self-matches clearly indicated
- Easy-to-read character names with bold formatting

## sf6stats.sh (unofficial Bash script)
- Reference: https://www.streetfighter.com/6/buckler/stats/dia
  - The JSON is downloaded to `$HOME/.cache/sf6stats/`
- `-h, --help`: For more information

### Example
```bash
# Stronger character?
./sf6stats.sh --rank master
```
```text
01 C-terry    54.51%
02 M-terry    53.90%
03 C-honda    51.44%
︙
```

```bash
# Easy fight?
./sf6stats.sh --rank master --chara C-guile
```
```text
58.72% M-dhalsim
57.37% M-ken
56.44% M-gouki
︙
```

## TODO
- [ ] Add the option to switch between "Control Type Total" and "By Control Type" stats.  
- [ ] Add support Character Usage Stats ([usagerate](https://www.streetfighter.com/6/buckler/api/en/stats/usagerate))
- [ ] Implement win rate trend analysis (comparing current month with previous months)
- [ ] Create a more detailed matchup analysis view based on different ranks.
- [ ] Add support for different output formats (CSV, JSON)
- [ ] Implement caching strategy for faster repeated queries
- [ ] Add unit tests for color formatting functions
- [ ] Create a man page for better documentation

## Contributing
Feel free to submit issues and enhancement requests!

## License
MIT License © 2024 Nekorobi
