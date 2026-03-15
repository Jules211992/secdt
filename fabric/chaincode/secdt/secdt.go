package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type SmartContract struct {
	contractapi.Contract
}

type DigitalTwinState struct {
	MachineID   string  `json:"machine_id"`
	Timestamp   string  `json:"timestamp"`
	CID         string  `json:"cid"`
	HealthScore float64 `json:"health_score"`
	Cycle       int     `json:"cycle"`
	SessionID   string  `json:"session_id"`
	Hash        string  `json:"hash"`
	TxID        string  `json:"tx_id"`
}

type MaintenanceAlert struct {
	MachineID string `json:"machine_id"`
	Timestamp string `json:"timestamp"`
	Reason    string `json:"reason"`
	TxID      string `json:"tx_id"`
}

func (s *SmartContract) RegisterState(ctx contractapi.TransactionContextInterface, machineID string, cid string, healthScore float64, cycle int, sessionID string, hash string) error {
	existing, err := ctx.GetStub().GetState(machineID)
	if err != nil {
		return fmt.Errorf("failed to read state: %v", err)
	}

	if existing != nil {
		var prev DigitalTwinState
		json.Unmarshal(existing, &prev)
		if prev.Hash == hash {
			return fmt.Errorf("duplicate state: hash already registered")
		}
	}

	state := DigitalTwinState{
		MachineID:   machineID,
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
		CID:         cid,
		HealthScore: healthScore,
		Cycle:       cycle,
		SessionID:   sessionID,
		Hash:        hash,
		TxID:        ctx.GetStub().GetTxID(),
	}

	stateJSON, err := json.Marshal(state)
	if err != nil {
		return fmt.Errorf("failed to marshal state: %v", err)
	}

	return ctx.GetStub().PutState(machineID, stateJSON)
}

func (s *SmartContract) VerifyIntegrity(ctx contractapi.TransactionContextInterface, machineID string, hash string) (bool, error) {
	stateJSON, err := ctx.GetStub().GetState(machineID)
	if err != nil {
		return false, fmt.Errorf("failed to read state: %v", err)
	}
	if stateJSON == nil {
		return false, fmt.Errorf("state not found for machine: %s", machineID)
	}

	var state DigitalTwinState
	err = json.Unmarshal(stateJSON, &state)
	if err != nil {
		return false, fmt.Errorf("failed to unmarshal state: %v", err)
	}

	return state.Hash == hash, nil
}

func (s *SmartContract) GetHistory(ctx contractapi.TransactionContextInterface, machineID string) ([]DigitalTwinState, error) {
	historyIterator, err := ctx.GetStub().GetHistoryForKey(machineID)
	if err != nil {
		return nil, fmt.Errorf("failed to get history: %v", err)
	}
	defer historyIterator.Close()

	var history []DigitalTwinState
	for historyIterator.HasNext() {
		record, err := historyIterator.Next()
		if err != nil {
			return nil, err
		}
		var state DigitalTwinState
		if !record.IsDelete {
			json.Unmarshal(record.Value, &state)
			history = append(history, state)
		}
	}
	return history, nil
}

func (s *SmartContract) TriggerMaintenance(ctx contractapi.TransactionContextInterface, machineID string, reason string) error {
	stateJSON, err := ctx.GetStub().GetState(machineID)
	if err != nil {
		return fmt.Errorf("failed to read state: %v", err)
	}
	if stateJSON == nil {
		return fmt.Errorf("machine not found: %s", machineID)
	}

	alert := MaintenanceAlert{
		MachineID: machineID,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Reason:    reason,
		TxID:      ctx.GetStub().GetTxID(),
	}

	alertJSON, err := json.Marshal(alert)
	if err != nil {
		return fmt.Errorf("failed to marshal alert: %v", err)
	}

	alertKey := "MAINTENANCE_" + machineID + "_" + ctx.GetStub().GetTxID()
	return ctx.GetStub().PutState(alertKey, alertJSON)
}

func main() {
	chaincode, err := contractapi.NewChaincode(&SmartContract{})
	if err != nil {
		fmt.Printf("Error creating chaincode: %v\n", err)
		return
	}
	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting chaincode: %v\n", err)
	}
}
