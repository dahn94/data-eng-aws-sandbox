# A imagem oficial do Glue, mais as dependências que o job declara na AWS.
#
# Na nuvem isso é `additional_python_modules` no aws_glue_job
# (workloads/amazonsales/main.tf). Aqui precisa estar na imagem: instalar à mão
# no contêiner funciona até o primeiro `docker compose down`, e aí o portão de
# qualidade falha com ModuleNotFoundError no meio da pipeline.
#
# A versão é a MESMA do main.tf de propósito. Divergir faria o local deixar de
# ser prova do que roda na nuvem.
FROM public.ecr.aws/glue/aws-glue-libs:5.0.10

RUN pip install --no-cache-dir great_expectations==1.21.0
