
<!-- README.md is generated from README.Rmd. Please edit that file -->

# devrel agent

A [commons agent](https://github.com/posit-dev/commons) for exploring
the adoption, engagement, and growth of Posit open-source projects.

<div align="center">

<img src="https://github.com/user-attachments/assets/34449dea-3c57-4ecc-87ae-f68a219460fa" alt="A screencast of the devrel agent answering a question about CRAN downloads, then plotting downloads over time." width="85%" />

</div>

The agent is more accurate, faster, and cheaper on devrel-related
questions than Claude Code placed in the devrel-io repository.

<div align="center">

<img src="man/figures/README-eval-plot-1.png" alt="Three bar charts compare the devrel agent with Claude Code. The devrel agent has higher mean accuracy, lower median solver time, and lower total cost." width="85%" />

</div>

The agent analyzes the
[devrel-io](https://github.com/posit-dev/devrel-io) data, which is an
automated collection of devrel metrics. devrel-io is built with
[posit-dev/velocirepo](https://github.com/posit-dev/velocirepo), a more
general data synthesis software.

## Refresh the data

The agent reads `data/velocirepo.duckdb` and its data dictionary,
`data/data-dict.yaml`. Both come from a clone of devrel-io in
`inst/devrel-io`, exported by velocirepo (1.2.0 or later):

``` bash
git -C inst/devrel-io pull
velocirepo --config inst/devrel-io/velocirepo.toml export data --data-dict
```

velocirepo writes the dictionary from the schema, the data and the
`[data_dict]` section of devrel-io’s `velocirepo.toml`. Caveats about
the data belong in that section, so they reach the dictionary at the
next export.
