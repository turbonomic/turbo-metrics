/*
Copyright 2023.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

type EntityConfiguration struct {
	// +kubebuilder:validation:Enum=application;databaseServer;virtualMachine
	Type          string                `json:"type"`
	HostedOnVM    bool                  `json:"hostedOnVM,omitempty"`
	MetricConfigs []MetricConfiguration `json:"metrics"`
	// AttributeConfigs specifies how to map labels into attributes
	// +kubebuilder:validation:MaxProperties:=1
	AttributeConfigs map[string]LabelMapping `json:"attributes"`
}

type LabelMapping struct {
	Label        string `json:"label"`
	Matches      string `json:"matches,omitempty"`
	As           string `json:"as,omitempty"`
	IsIdentifier bool   `json:"isIdentifier"`
}

type EntityStatus struct {
	Type  string `json:"type"`
	Count *int32 `json:"count"`
}
