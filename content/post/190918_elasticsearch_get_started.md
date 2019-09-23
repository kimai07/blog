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

APIリファレンス

- [Create index API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-create-index.html)
- [Delete index API](https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-delete-index.html)
- [cat APIs](https://www.elastic.co/guide/en/elasticsearch/reference/current/cat.html)


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

APIリファレンス

- [Index API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-index_.html)

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

APIリファレンス

- [Search](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-search.html)
- [URI Search](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-uri-request.html)
- 細かく検索条件をしていたい場合は以下を使用する
  - [Request Body Search](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-request-body.html)


## ドキュメント更新

今度はドキュメントIDが1のtitleフィールドを更新します。

```sh
$ curl -H "Content-Type: application/json" -XPOST 'localhost:9200/product/book/1/_update?pretty' -d '
{
  "doc" : {
      "title" : "Elasticsearch v7.3"
  }
}'
```

更新後もう一度検索してみると、titleフィールドの取得値が更新されていることが確認できます。

```sh
$ curl -XGET 'localhost:9200/product/_search?q=title:Elasticsearch&pretty'
{
  "took" : 7,
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
    "max_score" : 0.2876821,
    "hits" : [
      {
        "_index" : "product",
        "_type" : "book",
        "_id" : "1",
        "_score" : 0.2876821,
        "_source" : {
          "date" : "2019-09-15T18:19:57+09:00",
          "title" : "Elasticsearch v7.3",
          "desc" : "これはElasticsearchに関する商品です"
        }
      }
    ]
  }
}
```

APIリファレンス

- [Update API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update.html)
- [Update By Query API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update-by-query.html)



## ドキュメント削除

最後に、更新したドキュメントを削除してみます。

```
$ curl -XDELETE 'localhost:9200/product/book/1?pretty'
{
  "_index" : "product",
  "_type" : "book",
  "_id" : "1",
  "_version" : 4,
  "result" : "deleted",
  "_shards" : {
    "total" : 2,
    "successful" : 1,
    "failed" : 0
  },
  "_seq_no" : 3,
  "_primary_term" : 2
}
```

削除後にもう一度検索してみると、先程までヒットしていたドキュメントがヒットしなくなり、ドキュメントが正しく削除されていることが確認できます。

```sh
$ curl -XGET 'localhost:9200/product/_search?q=title:Elasticsearch&pretty'
{
  "took" : 713,
  "timed_out" : false,
  "_shards" : {
    "total" : 1,
    "successful" : 1,
    "skipped" : 0,
    "failed" : 0
  },
  "hits" : {
    "total" : {
      "value" : 0,
      "relation" : "eq"
    },
    "max_score" : null,
    "hits" : [ ]
  }
}
```

APIリファレンス

- [Delete API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-delete.html)
- [Delete by query API](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-delete-by-query.html)

## エラーメモ

APIリクエストを試す中でエラーとなったケースを列挙していく

#### ドキュメント更新リクエスト

フィールド指定が正しくない場合

```sh
$ curl -H "Content-Type: application/json" -XPOST 'localhost:9200/product/book/1/_update?pretty' -d '
{
  "doc" : {
      "title" : "Elasticsearch v7.3"
  }
}'
{
  "error" : {
    "root_cause" : [
      {
        "type" : "x_content_parse_exception",
        "reason" : "[1:2] [UpdateRequest] unknown field [title], parser not found"
      }
    ],
    "type" : "x_content_parse_exception",
    "reason" : "[1:2] [UpdateRequest] unknown field [title], parser not found"
  },
  "status" : 400
}
```

titleフィールドの指定で、 title文字列を `"` で囲まなかった場合

```sh
$ curl -H "Content-Type: application/json" -XPOST 'localhost:9200/product/book/1/_update?pretty' -d '
{
  "doc" : {
      "title" : "Elasticsearch v7.3"
  }
}'
{
  "error" : {
    "root_cause" : [
      {
        "type" : "json_parse_exception",
        "reason" : "Unexpected character ('t' (code 116)): was expecting double-quote to start field name\n at [Source: org.elasticsearch.transport.netty4.ByteBufStreamInput@3abb9f17; line: 1, column: 3]"
      }
    ],
    "type" : "json_parse_exception",
    "reason" : "Unexpected character ('t' (code 116)): was expecting double-quote to start field name\n at [Source: org.elasticsearch.transport.netty4.ByteBufStreamInput@3abb9f17; line: 1, column: 3]"
  },
  "status" : 500
}
```

POSTではなくPUTでリクエストしてしまった場合

```sh
$ curl -H "Content-Type: application/json" -XPUT 'localhost:9200/product/book/1/_update?pretty' -d '
{
  "doc" : {
      "title" : "Elasticsearch v7.3"
  }
}'
{
  "error" : "Incorrect HTTP method for uri [/product/book/1/_update?pretty] and method [PUT], allowed: [POST]",
  "status" : 405
}
```


