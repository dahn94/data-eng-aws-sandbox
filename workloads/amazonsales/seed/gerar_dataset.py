"""Gera o dataset de origem do amazonsales, de forma determinística.

O `stg_table` lê Parquet com o schema abaixo e deduplica por `product_id`. Este
gerador é o produtor que faltava: sem ele, nada no repositório publica o dado
que a pipeline consome, e nenhum ADR do amazonsales podia ser verificado.

**Determinismo é o requisito, não um detalhe.** Duas execuções com a mesma
semente produzem exatamente as mesmas linhas — é o que torna os números
comparáveis entre execuções e entre workloads (ver ../../DATASET.md).

De propósito, o dado tem **mais de uma linha por `product_id`**: são as
avaliações do mesmo produto. É isso que dá o que deduplicar ao
`adr/0002-dedup-do-cdc-na-staging`, e o que permite verificar que ele escolhe
uma linha por chave em vez de somar.

Uso, dentro do contêiner do lakehouse:

    spark-submit /workspace/workloads/amazonsales/seed/gerar_dataset.py \
      --saida s3a://sandbox-lake-raw-local/amazonsales/ \
      --produtos 50 --semente 42
"""

import os
import random
import sys

from pyspark.sql import SparkSession
from pyspark.sql.types import (
    DoubleType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)

SCHEMA = StructType([
    StructField("product_id", StringType()),
    StructField("product_name", StringType()),
    StructField("category", StringType()),
    StructField("discounted_price", DoubleType()),
    StructField("actual_price", DoubleType()),
    StructField("discount_percentage", DoubleType()),
    StructField("rating", DoubleType()),
    StructField("rating_count", IntegerType()),
    StructField("about_product", StringType()),
    StructField("user_id", StringType()),
    StructField("user_name", StringType()),
    StructField("review_id", StringType()),
    StructField("review_title", StringType()),
    StructField("review_content", StringType()),
    StructField("img_link", StringType()),
    StructField("product_link", StringType()),
])

CATEGORIAS = ["Eletronicos", "Casa", "Livros", "Esporte", "Beleza"]


def args_de(argv):
    valores = {"saida": None, "produtos": "50", "semente": "42", "max_avaliacoes": "3"}
    for i, a in enumerate(argv):
        if a.startswith("--") and i + 1 < len(argv):
            chave = a[2:]
            if chave in valores:
                valores[chave] = argv[i + 1]
    if not valores["saida"]:
        raise SystemExit("erro: --saida é obrigatório")
    return valores


def gerar(n_produtos, semente, max_avaliacoes):
    """Devolve as linhas. `random.Random(semente)` isola o estado global."""
    rnd = random.Random(semente)
    linhas = []
    for p in range(1, n_produtos + 1):
        pid = f"P{p:05d}"
        categoria = CATEGORIAS[p % len(CATEGORIAS)]
        preco_cheio = round(rnd.uniform(20, 500), 2)
        desconto = round(rnd.uniform(0, 60), 2)
        preco_final = round(preco_cheio * (1 - desconto / 100), 2)
        nota = round(rnd.uniform(1, 5), 1)
        # Mais de uma avaliação por produto: é o que o stg vai deduplicar.
        for r in range(1, rnd.randint(1, max_avaliacoes) + 1):
            u = rnd.randint(1, max(2, n_produtos // 2))
            linhas.append((
                pid,
                f"Produto {p}",
                categoria,
                preco_final,
                preco_cheio,
                desconto,
                nota,
                rnd.randint(10, 5000),
                f"Descricao do produto {p}",
                f"U{u:05d}",
                f"Usuario {u}",
                f"{pid}-R{r}",
                f"Titulo da avaliacao {r} do produto {p}",
                f"Conteudo da avaliacao {r} do produto {p}",
                f"https://exemplo.invalid/img/{pid}.jpg",
                f"https://exemplo.invalid/p/{pid}",
            ))
    return linhas


def main():
    args = args_de(sys.argv)
    linhas = gerar(int(args["produtos"]), int(args["semente"]), int(args["max_avaliacoes"]))

    construtor = SparkSession.builder.appName("amazonsales-seed")
    # Escrever em MinIO passa pelo S3A do Hadoop, que precisa saber o endereço,
    # o estilo de caminho e as credenciais.
    endpoint = os.environ.get("AWS_ENDPOINT_URL_S3", "")
    if endpoint:
        for esquema in ("s3", "s3a"):
            construtor = (
                construtor.config(f"spark.hadoop.fs.{esquema}.impl",
                                  "org.apache.hadoop.fs.s3a.S3AFileSystem")
                .config(f"spark.hadoop.fs.{esquema}.endpoint", endpoint)
                .config(f"spark.hadoop.fs.{esquema}.path.style.access", "true")
                .config(f"spark.hadoop.fs.{esquema}.access.key", os.environ.get("AWS_ACCESS_KEY_ID", ""))
                .config(f"spark.hadoop.fs.{esquema}.secret.key", os.environ.get("AWS_SECRET_ACCESS_KEY", ""))
                .config(f"spark.hadoop.fs.{esquema}.aws.credentials.provider",
                        "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
            )
    spark = construtor.getOrCreate()
    df = spark.createDataFrame(linhas, SCHEMA)

    distintos = df.select("product_id").distinct().count()
    print(f"SEMENTE          : {args['semente']}")
    print(f"LINHAS           : {df.count()}")
    print(f"PRODUTOS DISTINTOS: {distintos}")
    print(f"DUPLICATAS       : {df.count() - distintos}  (o que o stg deve descartar)")

    df.write.mode("overwrite").parquet(args["saida"])
    print(f"ESCRITO EM       : {args['saida']}")
    spark.stop()


if __name__ == "__main__":
    main()
