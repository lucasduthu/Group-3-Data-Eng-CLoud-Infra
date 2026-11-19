"""Effacement RGPD par pseudonymisation, étape 3 : le bronze (fichiers Parquet du bucket).

Le bronze est d'abord copié en local (gcloud storage rsync). Un fichier Parquet ne se modifie pas
ligne par ligne : chaque fichier qui contient la personne est relu, corrigé et réécrit, puis seuls
les fichiers modifiés sont renvoyés dans le bucket (gcloud storage cp).
- buyer_id / c_id égal à la cible -> remplacé par le pseudonyme de l'étape 2 (même pseudonyme partout)
- coordonnées (fname, lname, phone, email, street_address, zip) -> NULL
- titre et texte libre de ses avis (title, r_desc) -> NULL
- shipping_details n'a pas de c_id : ses adresses sont retrouvées par les address_id de customer_shipping
- toute autre colonne texte qui contient encore l'identifiant est SIGNALÉE, pas modifiée

Usage :
  python scripts/pseudonymize_bronze.py <identifiant> <pseudonyme> <dossier_local>            # dry run
  python scripts/pseudonymize_bronze.py <identifiant> <pseudonyme> <dossier_local> --apply    # réécrit
Chaque fichier modifié est listé sur une ligne « MODIFIED <chemin relatif> », pour le renvoi au bucket.
"""
import pathlib
import sys

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq

TARGET, PSEUDO, ROOT = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3]).expanduser()
APPLY = "--apply" in sys.argv
ID_COLS = ("buyer_id", "c_id")
CONTACT_COLS = ("fname", "lname", "phone", "email", "street_address", "zip", "title", "r_desc")

paths = sorted(ROOT.rglob("*.parquet"))


def read(path, columns=None):
    with open(path, "rb") as f:   # lecture du fichier seul, sans déduire de partition du chemin
        return pq.read_table(f, columns=columns)


def is_target(col):
    return pc.fill_null(pc.equal(col.combine_chunks(), TARGET), False)


def owner_mask(table):
    mask = pa.array([False] * table.num_rows, pa.bool_())
    for c in ID_COLS:
        if c in table.column_names:
            mask = pc.or_(mask, is_target(table[c]))
    return mask


# 1er passage : les adresses de la personne (customer_shipping relie c_id et address_id)
addresses = set()
for p in paths:
    names = pq.read_schema(p).names
    if "c_id" in names and "address_id" in names:
        t = read(p, ["c_id", "address_id"])
        addresses.update(t.filter(owner_mask(t))["address_id"].to_pylist())
print(f"{len(paths)} fichiers Parquet. Adresses de la personne : {sorted(addresses)}")

touched = residual = 0
for p in paths:
    rel = p.relative_to(ROOT).as_posix()
    t = read(p)
    names = t.column_names
    mask = owner_mask(t)
    if addresses and "address_id" in names and "street_address" in names:
        ids = pa.array(sorted(addresses), type=t["address_id"].type)
        mask = pc.or_(mask, pc.fill_null(pc.is_in(t["address_id"].combine_chunks(), value_set=ids), False))
    hits = pc.sum(pc.cast(mask, pa.int64())).as_py() or 0
    if hits:
        touched += 1
        cols = []
        for name in names:
            col = t[name].combine_chunks()
            if name in ID_COLS:
                col = pc.if_else(is_target(t[name]), pa.scalar(PSEUDO, col.type), col)
            elif name in CONTACT_COLS:
                col = pc.if_else(mask, pa.scalar(None, col.type), col)
            cols.append(col)
        new = pa.Table.from_arrays(cols, schema=t.schema)
        print(f"{hits:>4} ligne(s) {'réécrite(s)' if APPLY else 'à traiter'} : {rel}")
        if APPLY:
            pq.write_table(new, p, compression="snappy")
            print(f"MODIFIED {rel}")
        t = new
    for name in names:   # résidus : l'identifiant encore présent dans une autre colonne texte
        col = t[name].combine_chunks()
        if name not in ID_COLS and (pa.types.is_string(col.type) or pa.types.is_large_string(col.type)):
            n = pc.sum(pc.cast(pc.fill_null(pc.match_substring(col, TARGET), False), pa.int64())).as_py() or 0
            if n:
                residual += 1
                print(f"     RÉSIDU non modifié : {n} valeur(s) de {name} contiennent l'identifiant : {rel}")

print(f"{touched} fichier(s) {'réécrit(s)' if APPLY else 'concerné(s)'}, {residual} résidu(s) signalé(s)")
