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

import ballerina/http;
import 'service.representations as rep;
import 'service.mock;

configurable int port = ?;

# A fake mountain resort
@http:ServiceConfig { mediaTypeSubtypePrefix: "vnd.snowpeak.reservation", cors: { allowOrigins: ["*"]} }
service /snowpeak on new http:Listener(port) {

    # Represents Snowpeak location resource
    # 
    # + return - `Location` or `SnowpeakError` representation
    resource function get locations() returns @http:Cache rep:Locations|rep:SnowpeakError {
        do {
            return check mock:getLocations();
        } on fail var e {
            return { body: { msg: e.toString() }};
        }
    }

    # Reperesents Snowpeak room collection resource 
    # 
    # + id - Unique identification of location
    # + startDate - Start date in format yyyy-mm-dd
    # + endDate - End date in format yyyy-mm-dd
    # + return - `Rooms` or `SnowpeakError` representation
    resource function get locations/[string id]/rooms(string startDate, string endDate) 
                returns rep:Rooms|rep:SnowpeakError {
        do {
            return check mock:getRooms(startDate, endDate);
        } on fail var e {
            return { body: { msg: e.toString() }};
        }
    }

    # Represents Snowpeak reservation resource
    # 
    # + reservation - Reservation representation 
    # + return - `ReservationCreated`, `ReservationConflict` or `SnowpeakError` representation
    resource function post reservation(@http:Payload rep:Reservation reservation)
                returns rep:ReservationCreated|rep:ReservationConflict|rep:SnowpeakError {
        do {
            return check mock:createReservation(reservation);
        } on fail var e {
            return { body: { msg: e.toString() }};
        }
    }

    # Represents Snowpeak reservation resource
    # 
    # + reservation - Reservation representation 
    # + return - `ReservationCreated`, `ReservationConflict` or `SnowpeakError` representation
    resource function put reservation(@http:Payload rep:Reservation reservation) 
                returns rep:ReservationUpdated|rep:ReservationConflict|rep:SnowpeakError {
        do {
            return check mock:updateReservation(reservation);
        } on fail var e {
            return { body: { msg: e.toString() }};
        }
    }

    # Represents Snowpeak payment resource 
    # 
    # + id - Unique identification of payment
    # + payment - Payment representation
    # + return - `PaymentCreated`, `PaymentConflict` or `SnowpeakError` representation
    resource function post payment/[string id](@http:Payload rep:Payment payment) 
                returns rep:PaymentCreated|rep:PaymentConflict|rep:SnowpeakError {
        do {
            return check mock:createPayment(id, payment);
        } on fail var e {
            return { body: { msg: e.toString() }};
        }
    }
}
