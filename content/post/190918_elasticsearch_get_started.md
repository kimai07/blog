---
title: "Docker上のElasticsearchをcurlで操作する"
date: 2019-09-18T09:00:00+09:00
draft: false
---

## 概要

Docker 上の Elasticsearch を curl で API 操作してみます。

## 環境

```sh
$ sw_vers
ProductName:	Mac OS X
ProductVersion:	10.14.6
BuildVersion:	18G87
```

## Elasticsearch 用 docker-compose

今回は、docker コンテナを起動して、その中で Elasticsearch を起動します。
docker コンテナを起動するために、docker-compose を利用します。
Elasticsearch 用の Docker イメージや docker-compose.yml 等の情報は以下公式ドキュメントにまとまっています。

- [Install Elasticsearch with Docker \| Elasticsearch Reference | Elastic](https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html)

今回用いる docker-compose.yml は以下。

```yaml
version: "3.3"
services:
  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.3.0
    container_name: es01
    environment:
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - "discovery.type=single-node"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - esdata01:/usr/share/elasticsearch/data
    ports:
      - 9200:9200
    networks:
      - esnet

volumes:
  esdata01:
    driver: local

networks: esnet:
```

Docker コンテナ起動

```
$ docker-compose up
```

## curl で起動確認

Elasticsearch が起動されているかどうか curl で確認します。
デフォルトでは 9200 番ポートで API を利用。

```sh
$ curl localhost:9200
{
  "name" : "753d7d8524f6",
  "cluster_name" : "docker-cluster",
  "cluster_uuid" : "YVCIA1RzROi-AQ80Csa5CQ",
  "version" : {
    "number" : "7.3.0",
    "build_flavor" : "default",
    "build_type" : "docker",
    "build_hash" : "de777fa",
    "build_date" : "2019-07-24T18:30:11.767338Z",
    "build_snapshot" : false,
    "lucene_version" : "8.1.0",
    "minimum_wire_compatibility_version" : "6.8.0",
    "minimum_index_compatibility_version" : "6.0.0-beta1"
  },
  "tagline" : "You Know, for Search"
}
```

9200 ポート確認

```sh
$ lsof -i:9200
COMMAND    PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
com.docke 1502 user   17u  IPv6 0x3e5fb7c38bbe7217      0t0  TCP *:wap-wsp (LISTEN)
```

## インデックス作成

データ投入・検索を行う前にインデックスを作成します。
ここでは、インデックス名 `product` で作成。

```sh
$ curl -XPUT localhost:9200/product
{"acknowledged":true,"shards_acknowledged":true,"index":"product"}
```

上記コマンドの実行結果は、ワンラインで表示されるために見づらくなってしまいます。
見やすくするために、次のように`?pretty`を付与することで整形することが出来ます。（ `| jq .` でも同様）

```sh
$ curl -XPUT 'localhost:9200/product?pretty'
{
  "acknowledged" : true,
  "shards_acknowledged" : true,
  "index" : "product"
}
```

すでに作成済みのインデックスを作成しようとするとエラーになります。

```sh
$ curl -XPUT 'localhost:9200/product?pretty'
{
  "error" : {
    "root_cause" : [
      {
        "type" : "resource_already_exists_exception",
        "reason" : "index [product/43BfhxU6SUqNUcQ8dkDKAA] already exists",
        "index_uuid" : "43BfhxU6SUqNUcQ8dkDKAA",
        "index" : "product"
      }
    ],
    "type" : "resource_already_exists_exception",
    "reason" : "index [product/43BfhxU6SUqNUcQ8dkDKAA] already exists",
    "index_uuid" : "43BfhxU6SUqNUcQ8dkDKAA",
    "index" : "product"
  },
  "status" : 400
}
```

その場合は、一度インデックスを消して、再度作成を行います。

```sh
$ curl -XDELETE 'localhost:9200/product?pretty'
{
  "acknowledged" : true
}
```

作成されたインデックスを確認します。

```sh
$ curl 'localhost:9200/_cat/indices?v'
health status index   uuid                   pri rep docs.count docs.deleted store.size pri.store.size
yellow open   product Fz1qlOcwQyS-w0ZvKRmi4g   1   1          0            0       230b           230b
```

## データ投入

ここでは、ドキュメントが１つも入っていない状態で、新規にドキュメント登録を行います。
データ登録は `[インデックス名]/[タイプ]/[ドキュメントID]`  のように指定することで行うことが出来ます。

```sh
$ curl -H "Content-Type: application/json" -XPUT 'localhost:9200/product/book/1?pretty' -d '
{
  "date": "2019-09-15T18:19:57+09:00",
  "title": "Elasticsearch",
  "desc": "これはElasticsearchに関する商品です"
}'
{
  "_index" : "product",
  "_type" : "book",
  "_id" : "1",
  "_version" : 2,
  "result" : "updated",
  "_shards" : {
    "total" : 2,
    "successful" : 1,
    "failed" : 0
  },
  "_seq_no" : 1,
  "_primary_term" : 1
}
```

## 検索

登録したドキュメントを検索してみます。
検索は `[インデックス名]/_search`  のように指定することで行うことが出来ます。
検索キーワード・検索対象フィールドは、クエリパラメータとして `q=` の後に `フィールド名:検索キーワード` で指定できます。

```sh
$ curl -XGET 'localhost:9200/product/_search?q=title:Elasticsearch&pretty'
{
  "took" : 564,
  "timed_out" : false,
  "_shards" : {
    "total" : 1,
    "successful" : 1,
    "skipped" : 0,
    "failed" : 0
  },
  "hits" : {
    "total" : {
      "value" : 1,
      "relation" : "eq"
    },
    "max_score" : 0.18232156,
    "hits" : [
      {
        "_index" : "product",
        "_type" : "book",
        "_id" : "1",
        "_score" : 0.18232156,
        "_source" : {
          "date" : "2019-09-15T18:19:57+09:00",
          "title" : "Elasticsearch",
          "desc" : "これはElasticsearchに関する商品です"
        }
      }
    ]
  }
}
```

また、 `[インデックス名]/[タイプ]/_search`  と指定することで 特定のタイプのドキュメントを検索することが出来ます。

```sh
$ curl -XGET 'localhost:9200/product/book/_search?q=title:Elasticsearch&pretty'
{
  "took" : 9,
  "timed_out" : false,
  "_shards" : {
    "total" : 1,
    "successful" : 1,
    "skipped" : 0,
    "failed" : 0
  },
  "hits" : {
    "total" : {
      "value" : 1,
      "relation" : "eq"
    },
    "max_score" : 0.18232156,
    "hits" : [
      {
        "_index" : "product",
        "_type" : "book",
        "_id" : "1",
        "_score" : 0.18232156,
        "_source" : {
          "date" : "2019-09-15T18:19:57+09:00",
          "title" : "Elasticsearch",
          "desc" : "これはElasticsearchに関する商品です"
        }
      }
    ]
  }
}
```
