// Copyright (c) 2021 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/test;
import ballerina/lang.runtime as runtime;
import ballerina/http;
import ballerina/crypto;

final http:Client cacheClientEP = check new("http://localhost:" + cacheAnnotationTestPort1.toString(), 
    httpVersion = http:HTTP_1_1, cache = { enabled: false });

final http:Client cacheBackendEP = check new("http://localhost:" + cacheAnnotationTestPort2.toString(), 
    httpVersion = http:HTTP_1_1, cache = { isShared: true });

isolated int numberOfProxyHitsNew = 0;
isolated int noCacheHitCountNew = 0;
isolated int maxAgeHitCountNew = 0;
isolated int numberOfHitsNew = 0;
isolated int statusHits = 0;
final readonly & xml maxAgePayload1 = xml `<message>before cache expiration</message>`;
final readonly & xml maxAgePayload2 = xml `<message>after cache expiration</message>`;
readonly & string errorBody = "Error";
final readonly & string mustRevalidatePayload1 = "Hello, World!";
isolated byte[] mustRevalidatePayload2 = "Hello, New World!".toBytes();
final readonly & json nocachePayload1 = { "message": "1st response" };
final readonly & json nocachePayload2 = { "message": "2nd response" };
final readonly & http:Ok ok = {body : mustRevalidatePayload1};
final readonly & http:InternalServerError err = {body : errorBody};

service / on new http:Listener(cacheAnnotationTestPort1, httpVersion = http:HTTP_1_1) {

    resource function get noCache(http:Request req) returns http:Response|http:InternalServerError {
        http:Response|error response = cacheBackendEP->forward("/nocacheBE", req);
        if response is http:Response {
            return response;
        } else {
            http:InternalServerError errorRes = {body : response.message()};
            return errorRes;
        }
    }

    resource function get maxAge(http:Request req) returns http:Response|http:InternalServerError {
        http:Response|error response = cacheBackendEP->forward("/maxAgeBE", req);
        if response is http:Response {
            return response;
        } else {
            http:InternalServerError errorRes = {body : response.message()};
            return errorRes;
        }
    }

    resource function get mustRevalidate(http:Request req) returns http:Response|http:InternalServerError {
        lock {
            numberOfProxyHitsNew += 1;
        }
        http:Response|error response = cacheBackendEP->forward("/mustRevalidateBE", req);
        if response is http:Response {
            string numberOfHitsNewString = "";
            lock {
                numberOfHitsNewString = numberOfHitsNew.toString();
            }
            response.setHeader(serviceHitCount, numberOfHitsNewString);
            string numberOfProxyHitsNewString = "";
            lock {
                numberOfProxyHitsNewString = numberOfProxyHitsNew.toString();
            }
            response.setHeader(proxyHitCount, numberOfProxyHitsNewString);
            return response;
        } else {
            http:InternalServerError errorRes = {body : response.message()};
            return errorRes;
        }
    }

    resource function get statusResponse(http:Request req) returns http:Response|http:InternalServerError {
        http:Response|error response = cacheBackendEP->forward("/statusResponseBE", req);
        if response is http:Response {
            return response;
        } else {
            http:InternalServerError errorRes = {body : response.message()};
            return errorRes;
        }
    }
}

service / on new http:Listener(cacheAnnotationTestPort2, httpVersion = http:HTTP_1_1) {

    resource function default nocacheBE(http:Request req) returns @http:Cache{noCache : true, maxAge : -1,
            mustRevalidate : false} json {
        int count = 0;
        lock {
            noCacheHitCountNew += 1;
            count = noCacheHitCountNew;
        }
        if count == 1 {
            return nocachePayload1;
        } else {
            return nocachePayload2;
        }
    }

    resource function default maxAgeBE(http:Request req) returns @http:Cache{maxAge : 5, mustRevalidate : false} xml {
        int count = 0;
        lock {
            maxAgeHitCountNew += 1;
            count = maxAgeHitCountNew;
        }
        if count == 1 {
            return maxAgePayload1;
        } else {
            return maxAgePayload2;
        }
    }

    resource function get mustRevalidateBE(http:Request req) returns @http:Cache{maxAge : 5} string|byte[] {
        int count = 0;
        lock {
            numberOfHitsNew += 1;
            count = numberOfHitsNew;
        }
        if count < 2 {
            return mustRevalidatePayload1;
        } else {
            lock {
                return mustRevalidatePayload2.clone();
            }
        }
    }

    resource function get statusResponseBE(http:Request req) returns @http:Cache{noCache : true, maxAge : -1,
            mustRevalidate : false} http:Ok|http:InternalServerError {
        int count = 0;
        lock {
            statusHits += 1;
            count = statusHits;
        }
        if count < 3 {
            return ok;
        } else {
            return err;
        }
    }
}

@test:Config {}
function testNoCacheCacheControlWithAnnotation() returns error? {
    http:Response response = check cacheClientEP->get("/noCache");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    lock {
        test:assertEquals(noCacheHitCountNew, 1);
    }
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "no-cache,public");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(nocachePayload1.toString().toBytes()));
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), APPLICATION_JSON);
    assertJsonPayload(response.getJsonPayload(), nocachePayload1);

    response = check cacheClientEP->get("/noCache");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    lock {
        test:assertEquals(noCacheHitCountNew, 2);
    }
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "no-cache,public");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(nocachePayload2.toString().toBytes()));
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), APPLICATION_JSON);
    assertJsonPayload(response.getJsonPayload(), nocachePayload2);

    response = check cacheClientEP->get("/noCache");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    lock {
        test:assertEquals(noCacheHitCountNew, 3);
    }
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "no-cache,public");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(nocachePayload2.toString().toBytes()));
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), APPLICATION_JSON);
    assertJsonPayload(response.getJsonPayload(), nocachePayload2);
    return;
}

@test:Config {}
function testMaxAgeCacheControlWithAnnotation() returns error? {
    http:Response response = check cacheClientEP->get("/maxAge");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    lock {
        test:assertEquals(maxAgeHitCountNew, 1);
    }
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "public,max-age=5");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(maxAgePayload1.toString().toBytes()));
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), APPLICATION_XML);
    assertXmlPayload(response.getXmlPayload(), maxAgePayload1);

    response = check cacheClientEP->get("/maxAge");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    lock {
        test:assertEquals(maxAgeHitCountNew, 1);
    }
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "public,max-age=5");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(maxAgePayload1.toString().toBytes()));
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), APPLICATION_XML);
    assertXmlPayload(response.getXmlPayload(), maxAgePayload1);

    // Wait for a while before sending the next request
    runtime:sleep(5);

    response = check cacheClientEP->get("/maxAge");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    lock {
        test:assertEquals(maxAgeHitCountNew, 2);
    }
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "public,max-age=5");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(maxAgePayload2.toString().toBytes()));
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), APPLICATION_XML);
    assertXmlPayload(response.getXmlPayload(), maxAgePayload2);
    return;
}

@test:Config {}
function testMustRevalidateCacheControlWithAnnotation() returns error? {
    http:Response response = check cacheClientEP->get("/mustRevalidate");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "must-revalidate,public,max-age=5");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(mustRevalidatePayload1.toBytes()));
    assertHeaderValue(check response.getHeader(serviceHitCount), "1");
    assertHeaderValue(check response.getHeader(proxyHitCount), "1");
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), TEXT_PLAIN);
    assertTextPayload(response.getTextPayload(), mustRevalidatePayload1);

    response = check cacheClientEP->get("/mustRevalidate");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "must-revalidate,public,max-age=5");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(mustRevalidatePayload1.toBytes()));
    assertHeaderValue(check response.getHeader(serviceHitCount), "1");
    assertHeaderValue(check response.getHeader(proxyHitCount), "2");
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), TEXT_PLAIN);
    assertTextPayload(response.getTextPayload(), mustRevalidatePayload1);

    // Wait for a while before sending the next request
    runtime:sleep(5);

    response = check cacheClientEP->get("/mustRevalidate");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "must-revalidate,public,max-age=5");
    byte[] payload = [];
    lock {
        payload = mustRevalidatePayload2.clone();
    }
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(payload));
    assertHeaderValue(check response.getHeader(serviceHitCount), "2");
    assertHeaderValue(check response.getHeader(proxyHitCount), "3");
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), APPLICATION_BINARY);
    lock {
        assertBinaryPayload(response.getBinaryPayload(), payload);
    }
    return;
}

@test:Config {}
function testReturnStatusCodeResponsesWithAnnotation() returns error? {
    http:Response response = check cacheClientEP->get("/statusResponse");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    lock {
        test:assertEquals(statusHits, 1);
    }
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "no-cache,public");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(mustRevalidatePayload1.toBytes()));
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), TEXT_PLAIN);
    assertTextPayload(response.getTextPayload(), mustRevalidatePayload1);

    response = check cacheClientEP->get("/statusResponse");
    test:assertEquals(response.statusCode, 200, msg = "Found unexpected output");
    lock {
        test:assertEquals(statusHits, 2);
    }
    test:assertTrue(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CACHE_CONTROL), "no-cache,public");
    assertHeaderValue(check response.getHeader(ETAG), crypto:crc32b(mustRevalidatePayload1.toBytes()));
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), TEXT_PLAIN);
    assertTextPayload(response.getTextPayload(), mustRevalidatePayload1);

    response = check cacheClientEP->get("/statusResponse");
    test:assertEquals(response.statusCode, 500, msg = "Found unexpected output");
    lock {
        test:assertEquals(statusHits, 3);
    }
    test:assertFalse(response.hasHeader(ETAG));
    test:assertFalse(response.hasHeader(CACHE_CONTROL));
    test:assertFalse(response.hasHeader(LAST_MODIFIED));
    assertHeaderValue(check response.getHeader(CONTENT_TYPE), TEXT_PLAIN);
    assertTextPayload(response.getTextPayload(), errorBody);
    return;
}
