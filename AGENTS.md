This is the source code for an AI data analysis agent for developer relations data at Posit. The agent should be able to answer about the adoption, engagement, and growth across GitHub, PyPI, CRAN, Plausible, and OpenVSX of all Posit Open Source projects.

* The agent analyzes the posit-dev/devrel-io data, which is an automated collection of devrel metrics.
* devrel-io is built with posit-dev/velocirepo, a more general data synthesis software.
* The agent is built with posit-dev/commons, an R framework for agent building based on tidyverse/ellmer.

The goal is an agent that is more accurate, faster, and cheaper than Claude Code placed in the devrel-io repository.
