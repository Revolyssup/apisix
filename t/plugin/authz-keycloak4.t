#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
BEGIN {
    $ENV{VAULT_TOKEN} = "root";
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: set authz-keycloak conf: secret_key uses secret ref
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            -- put secret vault config
            local code, body = t('/apisix/admin/secrets/vault/test1',
                ngx.HTTP_PUT,
                [[{
                    "uri": "http://127.0.0.1:8200",
                    "prefix" : "kv/apisix",
                    "token" : "root"
                }]]
                )

            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            -- change consumer with secrets ref: vault
            code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "authz-keycloak": {
                            "token_endpoint": "https://127.0.0.1:8443/realms/University/protocol/openid-connect/token",
                            "permissions": ["course_resource#view"],
                            "client_id": "course_management",
                            "client_secret": "$secret://vault/test1/jack/secret_key",
                            "grant_type": "urn:ietf:params:oauth:grant-type:uma-ticket",
                            "timeout": 3000,
                            "ssl_verify": false,
                            "password_grant_token_generation_incoming_uri": "/api/token"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
                return ngx.say(body)
            end

            -- set route
            code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "authz-keycloak": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1982": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/api/token"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: store secret into vault
--- exec
VAULT_TOKEN='root' VAULT_ADDR='http://0.0.0.0:8200' vault kv put kv/apisix/jack secret_key=d1ec69e9-55d2-4109-a3ea-befa071579d5
--- response_body
Success! Data written to: kv/apisix/jack


=== TEST 3: verify: ok
--- config
location /t {
    content_by_lua_block {
        local json_decode = require("toolkit.json").decode
        local http = require "resty.http"
        local httpc = http.new()
        local uri = "http://127.0.0.1:" .. ngx.var.server_port .. "/api/token"
        local res, err = httpc:request_uri(uri, {
            method = "POST",
            headers = {
                ["Content-Type"] = "application/x-www-form-urlencoded",
            },

            body =  ngx.encode_args({
                username = "teacher@gmail.com",
                password = "123456",
            }),
        })

        if res.status == 200 then
            local body = json_decode(res.body)
            local accessToken = body["access_token"]
            local refreshToken = body["refresh_token"]

            if accessToken and refreshToken then
                ngx.say(true)
            else
                ngx.say(false)
            end
        else
            ngx.say(false)
        end
    }
}
--- request
GET /t
--- response_body
true
