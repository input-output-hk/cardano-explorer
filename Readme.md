# Disclaimer

:warning: Since 2020-02-13, development of these components has been split and moved to different locations :warning:.

- If you are an **existing API user** using the **current** Byron explorer API or transaction submission API, have a look at:

  https://github.com/input-output-hk/cardano-rest

  :warning: Note however that this project will no longer undergo feature updates and will not be updated for Shelley.
  
- If you are a **new API user** looking for long-term solutions which will also work with Shelley, have a look at:   

  https://github.com/input-output-hk/cardano-graphql
  
- If you are a **curious developer** keen on knowing the internals and understanding what happens behind the scene, you can dive into:

  https://github.com/input-output-hk/cardano-db-sync

# Cardano Explorer

The new cardano-explorer consists of a set of components:

* `cardano-explorer-db` which defines common data types and functions that are shared by the
  following two components. In particular, it defines the database schema.
* `cardano-explorer-node` which acts as a Cardano node, following the chain and inserting
  data from the chain into a PostgreSQL database.
* `cardano-explorer-webapi` which serves data from the PostgreSQL database via HTTP.
* `cardano-tx-submit-webapi` allows submission of pre-formed transmissions via a HTTP POST
  operation.


## Architecture

The explorer is written in a highly modular fashion to allow it to be as flexible as possible.

The `cardano-explorer-node` connects to a locally running `cardano-node` (ie one connected to other
nodes in the Cardano network over the internet with TCP/IP) using a Unix domain socket, retrieves
blocks and stores parts of each block in a local PostgreSQL database. The database does not store
things like cryptographic signatures but does store enough information to follow the chain of
blocks and look at the transactions within blocks.

The PostgreSQL database is designed to be accessed in a read-only fashion from other applications.
The database schema is highly normalised which helps prevent data inconsistencies (specifically
with the use of foreign keys from one table to another). More user friendly database queries can be
implemented using [Postgres Views][PostgresView] to implement joins between tables.

The `cardano-explorer-webapi` is a client than serves data from the PostgreSQL database as JSON via a
HTTP REST API.


## Further Reading

* [BuildingRunning][BuildingRunning]: Building and running the explorer node and webapi.
* [SchemaManagement][Schema Management]: How the database schema is managed and modified.
* [Validation][Validation]: Explanation of validation done by the explorer and assumptions made.

[BuildingRunning]: doc/building-running.md
[PostgresView]: https://www.postgresql.org/docs/current/sql-createview.html
[Schema Management]: doc/schema-management.md
[Validation]: doc/validation.md
